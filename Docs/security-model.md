# Security Model

## Trust Boundaries

- User input, speech transcripts, OCR text, screen snapshot metadata, barcode payloads, UI labels, local VLM output, and prior conversation text are untrusted.
- `cerberusApp` is trusted to present state and route observer-only screen requests.
- `cerberusCore` is trusted to enforce the screen-only tool allowlist, storage encryption, prompt-boundary escaping, and audit signing.

## Execution Rules

- The default app registers only `screen.snapshot`, `screen.ocr`, `screen.barcodes`, and `screen.ui_elements`.
- If `local-vlm.json` enables a valid local provider, the app also registers `screen.describe` as a read-only passive VQA tool.
- Foundation Models handle on-device text planning/answering and may call read-only screen tools; they do not receive raw screenshot pixels unless a tool returns a file path or extracted text.
- Vision OCR/barcode tools run locally through Apple frameworks and return extracted text, barcode payloads, geometry, and metadata.
- Optional VLM providers receive screenshot PNGs plus prompts through `screen.describe`; they are disabled by default and configured outside app settings.
- Screen tools are read-only and must fail closed when Screen Recording or Accessibility access is denied.
- No shipped app path exposes app control, shell execution, browser navigation, MCP calls, file search, Mail Automation, calendar/reminder writes, Finder reveal, Music controls, Shortcuts execution, or network web search.
- Local VLM HTTP providers must use localhost endpoints unless `allowNonLocalEndpoint` is explicitly set in config.
- A non-local VLM endpoint receives screenshots and prompts; use only trusted self-hosted endpoints and never enable it for stealth, cheating, or third-party screen observation.
- Disabled screen tools are omitted from planning prompts and rejected by the execution allowlist.

## Storage Rules

- App-owned files live under `~/Library/Application Support/cerberus/` or `~/Library/Caches/cerberus/`.
- Transcripts are AES-GCM encrypted with Keychain-stored keys.
- Audit logs are hash-chained and HMAC-signed with a Keychain-stored signing key.
- Screen snapshots are cached under `~/Library/Caches/cerberus/screen-snapshots/` and pruned by age/count.
- `screen.describe` writes temporary screenshot PNGs to the same cache family before handing the file path to the configured provider.
- Local VLM config lives at `~/Library/Application Support/cerberus/local-vlm.json`.
- VLM benchmark reports write to `.dist/validation/*.json`; generated golden images under `Fixtures/VLM/images/` are synthetic and contain no user screenshots.

## Review Checklist

- Confirm default catalog changes remain screen-only.
- Confirm optional `screen.describe` remains read-only and passive.
- Confirm VLM docs keep local-only disabled-by-default behavior and non-local screenshot egress warnings.
- Confirm new model-ingress payloads use prompt-boundary escaping.
- Confirm new write paths use `CerberusDirectories`.
- Confirm new permissions, entitlements, and `Info.plist` usage descriptions match observer-only shipped capabilities.
