# Security Model

## Trust Boundaries

- User input, speech transcripts, OCR text, screen snapshot metadata, barcode payloads, UI labels, local VLM output, and prior conversation text are untrusted.
- `cerberusApp` is trusted to present state and route observer-only screen requests.
- `cerberusCore` is trusted to enforce the screen-only tool allowlist, storage encryption, prompt-boundary escaping, and audit signing.

## Execution Rules

- The default app registers only `screen.snapshot`, `screen.ocr`, `screen.barcodes`, and `screen.ui_elements`.
- If `local-vlm.json` enables a valid local provider, the app also registers `screen.describe` as a read-only passive VQA tool.
- Screen tools are read-only and must fail closed when Screen Recording or Accessibility access is denied.
- No shipped app path exposes app control, shell execution, browser navigation, MCP calls, file search, Mail Automation, calendar/reminder writes, Finder reveal, Music controls, Shortcuts execution, or network web search.
- Local VLM HTTP providers must use localhost endpoints unless `allowNonLocalEndpoint` is explicitly set in config.
- Disabled screen tools are omitted from planning prompts and rejected by the execution allowlist.

## Storage Rules

- App-owned files live under `~/Library/Application Support/cerberus/` or `~/Library/Caches/cerberus/`.
- Transcripts are AES-GCM encrypted with Keychain-stored keys.
- Audit logs are hash-chained and HMAC-signed with a Keychain-stored signing key.
- Screen snapshots are cached under `~/Library/Caches/cerberus/screen-snapshots/` and pruned by age/count.
- Local VLM config lives at `~/Library/Application Support/cerberus/local-vlm.json`.

## Review Checklist

- Confirm default catalog changes remain screen-only.
- Confirm optional `screen.describe` remains read-only and passive.
- Confirm new model-ingress payloads use prompt-boundary escaping.
- Confirm new write paths use `CerberusDirectories`.
- Confirm new permissions, entitlements, and `Info.plist` usage descriptions match observer-only shipped capabilities.
