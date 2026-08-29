#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Users.Actions

# Manual, interactive verification of each piece of the pipeline before
# main.ps1 is run unattended. Not a substitute for automated tests -- there
# aren't any yet (see CLAUDE.md).

$root = Split-Path $PSScriptRoot -Parent
Import-Module "$root/modules/GenEmail.Config/GenEmail.Config.psm1" -Force
Import-Module "$root/modules/GenEmail.Connection/GenEmail.Connection.psm1" -Force
Import-Module "$root/modules/GenEmail.GraphMail/GenEmail.GraphMail.psm1" -Force
Import-Module "$root/modules/GenEmail.Ollama/GenEmail.Ollama.psm1" -Force

Write-Host "1. Loading config..."
$config = Get-GenEmailConfig
Write-Host "   OK. Sender=$($config.SenderMailbox) Recipient=$($config.RecipientMailbox) Model=$($config.OllamaModel)"

try {
    Write-Host "2. Connecting to tenant $($config.TenantId)..."
    $securePassword = ConvertTo-SecureString $config.CertificatePassword -AsPlainText -Force
    Connect-GenEmailTenant -TenantId $config.TenantId -AppId $config.AppId `
        -CertificatePath $config.CertificatePath -CertificatePassword $securePassword

    if (-not (Test-GenEmailConnection)) { throw "Connected but no active Graph context found." }
    Write-Host "   OK."

    Write-Host "3. Resolving sender/recipient mailboxes (requires User.Read.All)..."
    Get-GenEmailMailbox -UserId $config.SenderMailbox | Out-Null
    Get-GenEmailMailbox -UserId $config.RecipientMailbox | Out-Null
    Write-Host "   OK."

    Write-Host "4. Checking Ollama at $($config.OllamaBaseUrl)..."
    if (-not (Test-GenEmailOllamaConnection -BaseUrl $config.OllamaBaseUrl -Model $config.OllamaModel)) {
        throw "Ollama unreachable or model '$($config.OllamaModel)' not pulled."
    }
    Write-Host "   OK."

    Write-Host "5. Generating content (not sending yet)..."
    $content = New-GenEmailContent -Prompt $config.PromptTemplate `
        -Model $config.OllamaModel -BaseUrl $config.OllamaBaseUrl
    Write-Host "   Subject: $($content.Subject)"
    Write-Host "   Body:`n$($content.Body)"

    $answer = Read-Host "6. Send this email to $($config.RecipientMailbox)? (y/n)"
    if ($answer -eq 'y') {
        Send-GenEmailMail -FromMailboxId $config.SenderMailbox -ToAddress $config.RecipientMailbox `
            -Subject $content.Subject -Body $content.Body
        Write-Host "   Sent."
    }
    else {
        Write-Host "   Skipped."
    }
}
finally {
    Disconnect-GenEmailTenant
}
