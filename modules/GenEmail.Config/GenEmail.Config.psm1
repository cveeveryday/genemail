function Get-GenEmailConfig {
    [CmdletBinding()]
    param(
        [string]$Path = (Join-Path $PSScriptRoot '../../config.psd1')
    )

    if (-not (Test-Path $Path)) {
        throw "Config file not found at '$Path'. Copy config.example.psd1 to config.psd1 and fill in real values."
    }

    $data = Import-PowerShellDataFile -Path $Path

    $requiredKeys = @(
        'TenantId', 'AppId', 'CertificatePath', 'CertificatePassword',
        'SenderMailbox', 'RecipientMailbox',
        'OllamaBaseUrl', 'OllamaModel', 'PromptTemplate'
    )

    $missing = $requiredKeys | Where-Object {
        -not $data.ContainsKey($_) -or [string]::IsNullOrWhiteSpace([string]$data[$_])
    }
    if ($missing) {
        throw "Config at '$Path' is missing required value(s): $($missing -join ', ')"
    }

    [PSCustomObject]$data
}

Export-ModuleMember -Function Get-GenEmailConfig
