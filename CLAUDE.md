# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

genemail is a small PowerShell tool that generates an email with a locally-hosted LLM (via
**Ollama**) and sends it from one mailbox to another inside a **lab** Microsoft 365 tenant, using
**app-only Microsoft Graph auth** (certificate-based) as the sole data-plane entry point — no
SharePoint, no Exchange-specific SDK.

Everything lives inside this repo — no sibling repos, no external module dependencies beyond what's
listed in Prerequisites.

## Architecture

`main.ps1` is a thin orchestrator that imports four self-contained modules under `modules/` and runs
them in sequence: load config → connect → generate content → send → disconnect.

- **`GenEmail.Config`** — `Get-GenEmailConfig` loads and validates `config.psd1`, throwing one error
  listing every missing key rather than failing on the first.
- **`GenEmail.Connection`** — wraps `Connect-MgGraph` / `Disconnect-MgGraph` for certificate-based
  app-only auth. Loads the cert from a PFX file path (not a cert-store thumbprint) so it works the
  same on Linux as on Windows. `Test-GenEmailConnection` just checks `Get-MgContext` — a real
  Graph call isn't needed to prove auth worked since the mail-send call itself will surface failures.
- **`GenEmail.GraphMail`** — `Send-GenEmailMail` (wraps `Send-MgUserMail`), `Get-GenEmailMailbox`
  (wraps `Get-MgUser`, used for pre-flight mailbox validation), and `Get-GenEmailMessages` (wraps
  `Get-MgUserMessage`, reads recent messages from a mailbox). Keep this module mail-scoped; don't
  grow it into a general-purpose Graph wrapper.
- **`GenEmail.Ollama`** — `New-GenEmailContent` calls Ollama's `/api/generate` with `stream:false`
  (Ollama defaults to NDJSON streaming, which breaks a plain `Invoke-RestMethod` call) and parses a
  `SUBJECT: ...` / `BODY: ...` response — this format is far more reliable to parse out of a small
  local model than asking it to return JSON. Falls back to treating the whole response as the body
  if parsing fails, so a formatting drift never hard-fails the pipeline. `Test-GenEmailOllamaConnection`
  checks `/api/tags` for reachability and that the configured model is pulled.

`scripts/smoke-test.ps1` runs the same pipeline interactively, step by step, with a y/n gate before
actually sending — use it to verify a new environment/tenant before trusting `main.ps1` to run
unattended.

`scripts/seed-invoices.ps1 [-Count N] [-RecipientMailbox ...] [-RecipientMailbox2 ...]
[-SenderMailbox ...]` sends `N` synthetic invoice-notification emails (defaults from
`config.psd1`) to seed test data for something like an invoice-triage pipeline or a mailbox
forwarding rule. If `RecipientMailbox2` is set (in config or via `-RecipientMailbox2`), the *same*
generated message is sent to both addresses as a single email with two `To` recipients, not two
separate generations. Graph `sendMail` sends *as* whichever mailbox the app is authorized for;
app-only `Mail.ReadWrite` can't spoof an arbitrary external "From", so the fictional company only
ever appears in the subject/body/signature, never the SMTP envelope.

**Arithmetic is never done by the model.** `New-InvoiceData` computes the invoice number
(`INV-######`), PO number (`PO-######`), due date, 2-4 line items (quantity/unit price/line
total), and the grand total entirely in PowerShell using `[decimal]` math, so the total is
guaranteed correct by construction — a 7B local model was unreliable at this when asked to invent
*and* sum numbers itself. That data is serialized to compact JSON and handed to
`New-InvoicePrompt`, which tells the model to invent only prose (fictional company, item
descriptions, contact) around the fixed numbers and forbids it from recalculating anything. After
generation, the loop does a cheap sanity check — comma-stripped substring match of the computed
total against the returned body — and `Write-Warning`s (without blocking the send) if a model
ever fails to transcribe it faithfully. Because correctness no longer depends on model size,
`OllamaModel` defaults back to `qwen2.5:7b` (2-12s/email) rather than `gpt-oss:20b` (8-17s/email)
— pure formatting-around-given-numbers is an easy task even for the smaller model.

`Send-GenEmailMail`'s `-ToAddress` takes `string[]` (one or many recipients on the same message);
existing single-address callers (`main.ps1`, `scripts/smoke-test.ps1`) are unaffected since
PowerShell binds a lone string to a one-element array automatically.

## Configuration & secrets

Copy `config.example.psd1` to `config.psd1` (gitignored, along with `*.pfx`/`*.cer`) and fill in:
`TenantId`, `AppId`, `CertificatePath`, `CertificatePassword`, `SenderMailbox`, `RecipientMailbox`,
`OllamaBaseUrl`, `OllamaModel`, `PromptTemplate`. This is plaintext-on-disk, which is acceptable for
a personal lab tenant only — move `CertificatePassword` to
`Microsoft.PowerShell.SecretManagement`/`SecretStore` before this handles anything real.

## Entra app registration requirements

- **Microsoft Graph → Application permission → `Mail.ReadWrite`**, admin-consented. (Superset of
  `Mail.Send` — also allows `Get-GenEmailMessages` to read a mailbox's messages, not just send.)
- App-only `Mail.ReadWrite` is tenant-wide by default — the app can read/send as *any* mailbox unless
  scoped down. Restrict it to the lab mailbox(es) with an Exchange Online **Application Access
  Policy** (`New-ApplicationAccessPolicy` / `Test-ApplicationAccessPolicy`, via the
  `ExchangeOnlineManagement` module — a separate connection from Graph). Skipping this is a known,
  acceptable gap only in a throwaway lab tenant.
- `Get-GenEmailMailbox` (mailbox pre-flight check) additionally needs **`User.Read.All`**
  (Application). If you don't want to grant that, skip calling it — `Send-GenEmailMail` doesn't need
  it since Graph accepts a UPN/email directly. `User.Read.All` (no `-UserId` filter on `Get-MgUser`)
  is also what's needed to *list* mailboxes in the tenant rather than validate one you already know.
- Certificate auth: generate a cert, upload the public `.cer` to the app registration's
  "Certificates & secrets" blade, keep the private-key `.pfx` local and out of git.

## Prerequisites

- PowerShell 7+
- Microsoft.Graph PowerShell SDK, installed as individual submodules (not the full `Microsoft.Graph`
  meta-module, which is much slower to import): `Microsoft.Graph.Authentication`,
  `Microsoft.Graph.Users.Actions`, `Microsoft.Graph.Users`, `Microsoft.Graph.Mail`
- [Ollama](https://ollama.com) running locally with the configured model already pulled
  (`ollama pull <model>`) — whatever host runs `main.ps1` unattended needs this too, not just the
  dev machine
- An Entra app registration in the lab tenant per the requirements above

There is no build, lint, or automated test tooling in this repo. Run `pwsh ./scripts/smoke-test.ps1`
first to verify a new setup end to end, then `pwsh ./main.ps1` for the unattended run.
