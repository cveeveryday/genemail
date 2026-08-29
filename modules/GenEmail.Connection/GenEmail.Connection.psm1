function Connect-GenEmailTenant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$CertificatePath,
        [Parameter(Mandatory)][securestring]$CertificatePassword
    )

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw "Microsoft.Graph.Authentication module not found. Install with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    }

    if (-not (Test-Path $CertificatePath)) {
        throw "Certificate not found at '$CertificatePath'."
    }

    # Loaded from a PFX file path rather than a cert-store thumbprint so this
    # works the same on Linux hosts, which don't have a Windows-style cert store.
    $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $CertificatePath, $CertificatePassword
    )

    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -Certificate $cert -NoWelcome
}

function Disconnect-GenEmailTenant {
    [CmdletBinding()]
    param()
    Disconnect-MgGraph | Out-Null
}

function Test-GenEmailConnection {
    [CmdletBinding()]
    param()
    [bool](Get-MgContext)
}

Export-ModuleMember -Function Connect-GenEmailTenant, Disconnect-GenEmailTenant, Test-GenEmailConnection
