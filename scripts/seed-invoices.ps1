#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users.Actions

<#
Sends -Count synthetic invoice-notification emails, each purporting to be from a
different fictional company, to a single mailbox (e.g. invoices@companydomain).
Useful for seeding test data for an invoice-triage/processing pipeline in the lab
tenant. The Graph "From" stays whatever mailbox the app is authorized to send as
(config's SenderMailbox / -SenderMailbox) -- app-only Mail.ReadWrite can't spoof an
arbitrary external sender, so company identity lives in the generated subject/body
only, not the SMTP envelope.
#>
param(
    [int]$Count = 5,
    [string]$RecipientMailbox,
    [string]$RecipientMailbox2,
    [string]$SenderMailbox
)

$root = Split-Path $PSScriptRoot -Parent
Import-Module "$root/modules/GenEmail.Config/GenEmail.Config.psm1" -Force
Import-Module "$root/modules/GenEmail.Connection/GenEmail.Connection.psm1" -Force
Import-Module "$root/modules/GenEmail.GraphMail/GenEmail.GraphMail.psm1" -Force
Import-Module "$root/modules/GenEmail.Ollama/GenEmail.Ollama.psm1" -Force

# Rotated through the batch to steer Ollama toward varied invented companies/invoices
# rather than near-duplicate output on a static prompt -- not a list of fixed company
# names, just an industry hint each iteration.
$industries = @(
    'office supplies', 'IT consulting', 'freight and logistics', 'commercial cleaning',
    'marketing services', 'industrial parts manufacturing', 'cloud hosting',
    'corporate catering', 'graphic design', 'HVAC maintenance', 'legal services',
    'packaging materials'
)

# All arithmetic (quantities, unit prices, line totals, grand total) is computed
# here in PowerShell with [decimal] -- never by the model -- so the numbers in the
# sent email are guaranteed correct by construction. The model only invents prose
# (company name, item descriptions, contact) around fixed numbers it's told not to
# alter, which is also a much easier task than asking it to do arithmetic, so a
# smaller/faster model stays reliable.
function New-InvoiceData {
    $itemCount = Get-Random -Minimum 2 -Maximum 5
    $lineItems = for ($i = 0; $i -lt $itemCount; $i++) {
        $quantity = Get-Random -Minimum 1 -Maximum 21
        $unitPrice = [math]::Round([decimal](Get-Random -Minimum 1500 -Maximum 300000) / 100, 2)
        [PSCustomObject]@{
            quantity  = $quantity
            unitPrice = $unitPrice
            lineTotal = [math]::Round($quantity * $unitPrice, 2)
        }
    }

    $total = [decimal]0
    foreach ($item in $lineItems) { $total += $item.lineTotal }

    [PSCustomObject]@{
        invoiceNumber = 'INV-{0:D6}' -f (Get-Random -Minimum 100000 -Maximum 999999)
        poNumber      = 'PO-{0:D6}' -f (Get-Random -Minimum 100000 -Maximum 999999)
        dueDate       = (Get-Date).AddDays((Get-Random -Minimum 15 -Maximum 46)).ToString('yyyy-MM-dd')
        lineItems     = @($lineItems)
        totalAmount   = [math]::Round($total, 2)
    }
}

function New-InvoicePrompt {
    param([string]$Industry, [string]$InvoiceDataJson)
    # Single-quoted here-string + -f substitution (not "@...@" interpolation) so the
    # embedded JSON's own double quotes / braces don't fight PowerShell's
    # $-interpolation rules.
    $template = @'
You are simulating a vendor's accounts-receivable department emailing an invoice to
a customer's accounts-payable inbox. Invent a plausible, entirely fictional company
name in the {0} industry -- do not use any real, existing company.

Here is the exact invoice data, already calculated, as JSON:
{1}

Write a short, professional invoice-notification email using these EXACT numbers --
do not recalculate, round, or change any quantity, unit price, line total, invoice
number, PO number, or the total amount. Your only jobs are: invent a one-line
description of plausible goods/services (fitting the {0} industry) for each line
item in the JSON, and write the prose around the given numbers. Format each line
item as:
<your invented description> - qty <quantity> x <unitPrice> USD = <lineTotal> USD
using the quantity/unitPrice/lineTotal values from the matching JSON line item, in
the same order. End with: Total Amount Due: <totalAmount> USD (the exact value from
the JSON). State the invoiceNumber, poNumber, and dueDate from the JSON verbatim.

Every value in the email must be either from the JSON verbatim or a concrete,
invented specific -- never a bracketed placeholder of any kind (no [Date], [Your
Name], [Customer Company Name], [Your Company Name], [phone number], [email
address], or anything else in brackets). Address the greeting generically to "Dear
Accounts Payable Team," without naming the recipient company at all. Never use the
words "attached," "enclosed," or "find attached" anywhere -- there is no
attachment, the itemized details above are the entire invoice. Sign off with the
fictional company's name and a fictional contact name and title.

Respond only in this exact format:
SUBJECT: <subject line>
BODY: <email body>
'@
    $template -f $Industry, $InvoiceDataJson
}

try {
    $config = Get-GenEmailConfig
    $to = @($(if ($RecipientMailbox) { $RecipientMailbox } else { $config.RecipientMailbox }))
    $to2 = if ($RecipientMailbox2) { $RecipientMailbox2 } else { $config.RecipientMailbox2 }
    if ($to2) { $to += $to2 }
    $from = if ($SenderMailbox) { $SenderMailbox } else { $config.SenderMailbox }

    Write-Host "Connecting to tenant $($config.TenantId)..."
    $securePassword = ConvertTo-SecureString $config.CertificatePassword -AsPlainText -Force
    Connect-GenEmailTenant -TenantId $config.TenantId -AppId $config.AppId `
        -CertificatePath $config.CertificatePath -CertificatePassword $securePassword

    if (-not (Test-GenEmailConnection)) { throw "Connected but no active Graph context found." }

    if (-not (Test-GenEmailOllamaConnection -BaseUrl $config.OllamaBaseUrl -Model $config.OllamaModel)) {
        throw "Ollama unreachable or model '$($config.OllamaModel)' not pulled at $($config.OllamaBaseUrl)."
    }

    Write-Host "Sending $Count synthetic invoice email(s) from $from to $($to -join ', ')`n"

    $sent = 0
    $failed = 0
    for ($i = 0; $i -lt $Count; $i++) {
        $industry = $industries[$i % $industries.Count]
        try {
            $invoiceData = New-InvoiceData
            $invoiceJson = $invoiceData | ConvertTo-Json -Depth 5 -Compress

            $content = New-GenEmailContent `
                -Prompt (New-InvoicePrompt -Industry $industry -InvoiceDataJson $invoiceJson) `
                -Model $config.OllamaModel -BaseUrl $config.OllamaBaseUrl

            # The model shouldn't be recalculating the total, but it's still free-text
            # output -- verify the exact computed total actually made it into the body
            # rather than silently trusting the model transcribed it correctly. Strip
            # thousands-separator commas first since the model may add them for
            # readability (e.g. "$60,073.74") without changing the underlying value.
            $expectedTotal = $invoiceData.totalAmount.ToString('0.00')
            if (($content.Body -replace ',', '') -notlike "*$expectedTotal*") {
                Write-Warning "[$($i + 1)/$Count] Model output doesn't contain the exact computed total ($expectedTotal) -- sending anyway, but check the body."
            }

            Send-GenEmailMail -FromMailboxId $from -ToAddress $to `
                -Subject $content.Subject -Body $content.Body

            $sent++
            Write-Host "[$($i + 1)/$Count] Sent: $($content.Subject) (total=$($invoiceData.totalAmount.ToString('0.00')) USD, $($invoiceData.lineItems.Count) line items)"
        }
        catch {
            $failed++
            Write-Warning "[$($i + 1)/$Count] Failed ($industry): $_"
        }
    }

    Write-Host "`nDone. Sent=$sent Failed=$failed"
    if ($failed -gt 0) { exit 1 }
}
finally {
    Disconnect-GenEmailTenant
}
