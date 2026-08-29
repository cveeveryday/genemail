@{
    # Entra ID app registration (lab tenant), certificate-based app-only auth
    TenantId            = '<tenant-guid-or-domain>'
    AppId               = '<entra-app-registration-client-id>'
    CertificatePath     = '<path-to-local-pfx-file>'
    CertificatePassword = '<pfx-password>'

    # Lab tenant mailboxes this app is scoped to via an Exchange Online
    # Application Access Policy (see CLAUDE.md)
    SenderMailbox       = 'sender@<lab-tenant>.onmicrosoft.com'
    RecipientMailbox    = 'recipient@<lab-tenant>.onmicrosoft.com'
    # Optional -- scripts/seed-invoices.ps1 also sends to this address (same message,
    # second To recipient) when set; omit this key or leave blank to send to just
    # RecipientMailbox.
    RecipientMailbox2   = ''

    # Local Ollama instance used to generate the email content
    OllamaBaseUrl       = 'http://localhost:11434'
    OllamaModel         = 'llama3.1'
    PromptTemplate      = "Write a short status-update email. Respond only in this exact format:`nSUBJECT: <subject line>`nBODY: <email body>"
}
