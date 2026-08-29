#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users.Actions

Import-Module "$PSScriptRoot/modules/GenEmail.Config/GenEmail.Config.psm1" -Force
Import-Module "$PSScriptRoot/modules/GenEmail.Connection/GenEmail.Connection.psm1" -Force
Import-Module "$PSScriptRoot/modules/GenEmail.GraphMail/GenEmail.GraphMail.psm1" -Force
Import-Module "$PSScriptRoot/modules/GenEmail.Ollama/GenEmail.Ollama.psm1" -Force

try {
    $config = Get-GenEmailConfig

    $securePassword = ConvertTo-SecureString $config.CertificatePassword -AsPlainText -Force
    Connect-GenEmailTenant -TenantId $config.TenantId -AppId $config.AppId `
        -CertificatePath $config.CertificatePath -CertificatePassword $securePassword

    $content = New-GenEmailContent -Prompt $config.PromptTemplate `
        -Model $config.OllamaModel -BaseUrl $config.OllamaBaseUrl

    Send-GenEmailMail -FromMailboxId $config.SenderMailbox -ToAddress $config.RecipientMailbox `
        -Subject $content.Subject -Body $content.Body

    Write-Host "Sent '$($content.Subject)' from $($config.SenderMailbox) to $($config.RecipientMailbox)"
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Disconnect-GenEmailTenant
}
