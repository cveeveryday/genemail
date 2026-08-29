# genreference.md — local-LLM + Graph delivery pipeline

This repo currently generates and sends an email. That's one instantiation of a more
general, reusable pipeline shape. This document describes that shape independent of
"email," so the same skeleton can be retargeted at a different generation task and a
different Graph delivery surface — e.g. generating a `.docx` from a source of
knowledge and filing it into an organized SharePoint document library.

## The pipeline shape

Five stages, run in sequence by a thin orchestrator (`main.ps1`), each owned by one
self-contained module:

1. **Config** — load and validate a `config.psd1`, fail loudly with every missing key
   at once rather than one at a time.
2. **Connect** — authenticate app-only against Microsoft Graph with a certificate,
   independent of what the pipeline does once connected.
3. **Generate** — call a local Ollama model to produce content. Never let the model
   compute facts (numbers, dates, IDs) it should transcribe verbatim — compute those
   in code, hand them to the model as fixed input, and sanity-check they survived in
   the output.
4. **Deliver** — push the generated content through a Graph data-plane call scoped
   narrowly to the one thing this pipeline does (send mail; upload a file). Don't let
   this module grow into a general-purpose Graph wrapper.
5. **Disconnect** — tear down the Graph session, always, via `finally`.

Design properties worth preserving in any retarget:

- **One module per concern, named for the concern, not the task.** `GenEmail.Config`,
  `GenEmail.Connection`, `GenEmail.Ollama` are already task-agnostic; only
  `GenEmail.GraphMail` is task-specific (mail-send/read). A retarget mainly means
  swapping that one module for a differently-scoped one and adjusting `Generate` to
  produce what the new `Deliver` module expects.
- **Cert-from-PFX-path auth, not cert-store thumbprint** — works identically on
  Linux and Windows, and stays reusable regardless of what the app does after
  connecting.
- **`stream:false` on every Ollama `/api/generate` call** — Ollama defaults to NDJSON
  streaming, which breaks a plain `Invoke-RestMethod` call, regardless of task.
- **Structured-tag parsing over the model's response** (`SUBJECT: ... / BODY: ...`
  today) is far more reliable to extract from a small local model than asking it for
  JSON. Always keep a fallback (e.g. "if parsing fails, treat the whole response as
  the body") so a formatting drift never hard-fails the pipeline — generalize the tag
  set to whatever fields the new task needs (e.g. `TITLE: / SECTION: ...`).
- **Arithmetic/facts are computed in PowerShell, never invented or recalculated by
  the model.** The model's job is prose around fixed values; a cheap post-generation
  substring check (comma-stripped) confirms the exact computed value made it into the
  output, and only `Write-Warning`s (never blocks) on a miss. This generalizes to any
  fact the pipeline already knows and just needs the model to write prose around.
  See `scripts/seed-invoices.ps1`'s `New-InvoiceData` / total-transcription check for
  the concrete pattern.
- **Least-privilege delivery scope, restricted outside the Graph permission grant
  itself.** Mail today uses an Exchange Online Application Access Policy to pin
  tenant-wide `Mail.ReadWrite` down to specific mailboxes. Any Graph resource type
  being written to needs the analogous per-resource restriction, not just the
  application permission (see the SharePoint note below) — the Entra app permission
  alone is usually tenant-wide.
- **A smoke-test script that walks the pipeline interactively with a y/n gate before
  the one irreversible step** (send / upload / whatever "deliver" does), so a new
  environment or new task can be verified before `main.ps1` runs unattended.

## Current instantiation: email (this repo)

| Stage | Module | Graph/local call | Task-specific bit |
|---|---|---|---|
| Config | `GenEmail.Config` | — | required keys list |
| Connect | `GenEmail.Connection` | `Connect-MgGraph` (cert) | none — fully reusable |
| Generate | `GenEmail.Ollama` | `POST /api/generate` | `SUBJECT:`/`BODY:` tags, prompt template |
| Deliver | `GenEmail.GraphMail` | `Send-MgUserMail` | mailbox IDs, `Mail.ReadWrite` |
| Disconnect | `GenEmail.Connection` | `Disconnect-MgGraph` | none — fully reusable |

## Worked alternate instantiation: knowledge → docx → SharePoint library

To retarget this pipeline at "generate a `.docx` from a source of knowledge and file
it into an organized SharePoint library," each stage changes as follows.

**Config** — keep `TenantId`/`AppId`/`CertificatePath`/`CertificatePassword`/
`OllamaBaseUrl`/`OllamaModel` as-is. Replace mailbox keys with:
- `KnowledgeSourcePath` — file or folder fed into the prompt as grounding context
- `SiteId` (or `SiteUrl`) and `DriveId` (or library display name) — the target
  SharePoint site/library
- `DestinationFolderPath` — where in the library to file the doc (e.g.
  `/Reports/{Year}/{Month}` built at generate time for "organized" filing)
- `DocumentTemplatePath` — optional `.docx` template to fill rather than build from
  scratch (simplifies the render step below)

**Connect** — `GenEmail.Connection` is reused unchanged. Only the Graph permission
and its scoping mechanism change: `Sites.ReadWrite.All` (Application) instead of
`Mail.ReadWrite`, admin-consented. Prefer Graph's **`Sites.Selected`** permission
plus a per-site `Add-MgSitePermission` grant over tenant-wide `Sites.ReadWrite.All`
— the SharePoint equivalent of mail's Application Access Policy, i.e. don't skip the
scoping-down step just because the mechanism differs from Exchange Online's.

**Generate** — two sub-steps, where email only needed one:
1. *Content generation* (same shape as today): prompt Ollama with the knowledge
   source as context, parse a structured response — e.g. `TITLE:` / one or more
   `SECTION: <heading> / <body>` blocks — with the same "fall back to raw text on
   parse failure" safety net. Any facts pulled from the knowledge source that must
   appear verbatim (figures, names, dates) should be extracted in code and handed to
   the model as fixed input, then verified present in the output — same pattern as
   the invoice total check.
2. *Rendering to `.docx`* — new step with no analog in the mail pipeline, since
   Ollama only produces text. Simplest approach: open `DocumentTemplatePath` (a
   `.docx` with placeholder bookmarks) via the OpenXML SDK (`DocumentFormat.OpenXml`,
   loadable from PowerShell via `Add-Type`) and substitute the generated
   title/sections into it; avoids hand-rolling OOXML. Keep this as its own module
   (e.g. `GenEmail.DocxRender`) so `Generate`'s LLM-calling half stays reusable
   independent of the output file format.

**Deliver** — replace `GenEmail.GraphMail` with a module scoped to file upload only
(e.g. `GenEmail.GraphFiles`), wrapping Graph's drive-item upload:
`PUT /sites/{site-id}/drive/root:/{DestinationFolderPath}/{filename}:/content` for
files under 4 MB (an upload session is needed above that, unlikely for a generated
doc). Creating `DestinationFolderPath` first (if absent) is a small additional Graph
call this module owns, analogous to how `GraphMail` owns `Get-GenEmailMailbox`
pre-flight validation today.

**Disconnect** — `GenEmail.Connection`'s `Disconnect-GenEmailTenant` is reused
unchanged.

## Retargeting checklist

When pointing this skeleton at a new task:

- [ ] Config: keep the four auth keys; swap task-specific keys; update the
      required-keys list in `Get-GenEmailConfig`
- [ ] Connect: reuse as-is; only the Entra app's Graph permission grant changes
- [ ] Generate: decide the structured-tag format for the new content shape; keep the
      parse-failure fallback; identify any facts that must be computed/extracted in
      code rather than invented, and add the post-generation transcription check
- [ ] Generate (if the deliverable isn't plain text): add a rendering sub-step that
      turns the model's structured text into the final file format
- [ ] Deliver: write a narrowly-scoped module for the one Graph write this task
      needs; don't fold unrelated Graph calls into it
- [ ] Confirm least-privilege scoping exists for the new resource type, not just the
      Graph application permission (Application Access Policy for mail,
      `Sites.Selected` for SharePoint, etc.)
- [ ] Disconnect: reuse as-is
- [ ] Add/update a smoke-test script with a y/n gate before the irreversible step
