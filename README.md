# genemail

A small PowerShell pipeline that generates an email with a locally-hosted LLM (via
[Ollama](https://ollama.com)) and sends it from one mailbox to another inside a **lab** Microsoft
365 tenant, using **app-only Microsoft Graph auth** (certificate-based) as the sole data-plane
entry point — no SharePoint, no Exchange-specific SDK.

## How it works

`main.ps1` is a thin orchestrator that runs four self-contained modules in sequence:

1. **Config** — load and validate `config.psd1`, failing loudly with every missing key at once.
2. **Connect** — authenticate app-only against Microsoft Graph with a certificate.
3. **Generate** — call a local Ollama model to produce a subject/body.
4. **Deliver** — send the generated content via Graph, then disconnect.

See [`CLAUDE.md`](CLAUDE.md) for full module-by-module architecture notes, and
[`genreference.md`](genreference.md) for the task-agnostic version of this pipeline shape
(useful if you want to retarget it at something other than email).

## Prerequisites

- PowerShell 7+
- Microsoft.Graph PowerShell SDK, installed as individual submodules (not the full
  `Microsoft.Graph` meta-module, which is much slower to import):
  `Microsoft.Graph.Authentication`, `Microsoft.Graph.Users.Actions`, `Microsoft.Graph.Users`,
  `Microsoft.Graph.Mail`
- [Ollama](https://ollama.com) running locally with the configured model already pulled
  (`ollama pull <model>`) — whatever host runs `main.ps1` unattended needs this too, not just the
  dev machine
- An Entra app registration in a **lab** tenant (see below) — this tool is not intended for
  production tenants

## Entra app registration

- **Microsoft Graph → Application permission → `Mail.ReadWrite`**, admin-consented (superset of
  `Mail.Send`; also lets the pipeline read a mailbox's messages, not just send).
- App-only `Mail.ReadWrite` is tenant-wide by default — restrict it to your lab mailbox(es) with
  an Exchange Online **Application Access Policy** (`New-ApplicationAccessPolicy`, via the
  `ExchangeOnlineManagement` module).
- Mailbox pre-flight validation additionally needs **`User.Read.All`** (Application) — skip it if
  you don't want to grant that.
- Generate a certificate, upload the public `.cer` to the app registration's "Certificates &
  secrets" blade, keep the private-key `.pfx` local and out of git.

## Setup

1. Copy `config.example.psd1` to `config.psd1` (already gitignored, along with `*.pfx`/`*.cer`)
   and fill in your tenant/app/certificate/mailbox details.
2. Put your `.pfx` certificate somewhere local and point `CertificatePath` at it.
3. Pull the Ollama model you configured: `ollama pull <model>`.
4. Run the smoke test first — it walks through config, connection, mailbox resolution, and
   Ollama checks step by step, then asks for `y`/`n` confirmation before actually sending:

   ```
   pwsh ./scripts/smoke-test.ps1
   ```

5. Once that passes end-to-end, run the unattended pipeline:

   ```
   pwsh ./main.ps1
   ```

## Other scripts

- `scripts/seed-invoices.ps1 [-Count N] [-RecipientMailbox ...] [-RecipientMailbox2 ...] [-SenderMailbox ...]`
  — sends `N` synthetic invoice-notification emails to seed test data for something like an
  invoice-triage pipeline or a mailbox forwarding rule. Invoice numbers, PO numbers, dates, and
  totals are computed in PowerShell (never by the model), so the arithmetic is guaranteed
  correct — the model only invents surrounding prose.

## Configuration & secrets

`config.psd1` is plaintext-on-disk, which is acceptable for a personal lab tenant only — move
`CertificatePassword` to `Microsoft.PowerShell.SecretManagement`/`SecretStore` before pointing
this at anything real.

## Status

No automated tests yet. Run `pwsh ./scripts/smoke-test.ps1` to verify a new setup end to end.
