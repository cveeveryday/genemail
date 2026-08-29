function Send-GenEmailMail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FromMailboxId,
        [Parameter(Mandatory)][string[]]$ToAddress,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [ValidateSet('Text', 'HTML')][string]$BodyContentType = 'Text'
    )

    $message = @{
        Subject      = $Subject
        Body         = @{
            ContentType = $BodyContentType
            Content     = $Body
        }
        ToRecipients = @(
            $ToAddress | ForEach-Object { @{ EmailAddress = @{ Address = $_ } } }
        )
    }

    try {
        Send-MgUserMail -UserId $FromMailboxId -Message $message -SaveToSentItems:$false -ErrorAction Stop
    }
    catch {
        throw "Failed to send mail from '$FromMailboxId' to '$($ToAddress -join ', ')': $_"
    }
}

function Get-GenEmailMailbox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UserId
    )
    # Requires User.Read.All (Application) in addition to Mail.ReadWrite — skip calls
    # to this function if you don't want to grant that extra permission;
    # Send-GenEmailMail works from Mail.ReadWrite alone since Graph accepts a UPN directly.
    Get-MgUser -UserId $UserId -ErrorAction Stop
}

function Get-GenEmailMessages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UserId,
        [int]$Top = 10
    )
    try {
        Get-MgUserMessage -UserId $UserId -Top $Top -OrderBy 'receivedDateTime desc' -ErrorAction Stop
    }
    catch {
        throw "Failed to read mail for '$UserId': $_"
    }
}

Export-ModuleMember -Function Send-GenEmailMail, Get-GenEmailMailbox, Get-GenEmailMessages
