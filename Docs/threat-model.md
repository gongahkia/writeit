# Threat Model Notes

## Prompt Injection

OCR text, screen snapshot metadata, barcode payloads, UI labels, local VLM output, and prior conversation text can contain hostile instructions. VLM image fixtures include prompt-injection cases for this reason. The app wraps tool payloads as untrusted blocks and escapes matching closing delimiters before model ingress. New tool families must keep payload data separate from system/developer instructions.

## Tool Misuse

The primary misuse risk is a model plan that attempts to operate the computer instead of observing it. Mitigations are a screen-only default catalog, per-session screen-tool allowlists, no shipped mutating tool registration, no shell/MCP/browser/app-control exposure, and explicit observer-only prompt rules.

Optional local VLM support adds a screenshot egress risk. Mitigations are disabled-by-default registration, localhost-only HTTP endpoint validation, explicit `allowNonLocalEndpoint` opt-in for remote hosts, settings disclosure, and documentation that remote endpoints receive screenshots. Non-local VLM endpoints are not private by default; they receive the screenshot image and prompt.

Refuse stealth, cheating, proctoring, and UI-control requests, including "hide from screen sharing", "answer this exam from the screen without detection", "click/type using the vision model", and "watch someone without them knowing". `screen.describe` must remain passive observation: summarize visible state, report uncertainty, and refuse operation instructions.

## Local Data Storage

The primary local data risks are plaintext transcripts, tampered audit entries, and unbounded screen snapshots. Mitigations are AES-GCM encrypted transcript stores, Keychain-backed keys, HMAC-signed audit hash chains, app-owned path tests, cache retention for screen snapshots, and rollback instructions for deleting app data and Keychain entries.

## Residual Risks

- Screen snapshots may include sensitive visible content until cache pruning or user deletion.
- Accessibility UI labels may expose sensitive visible app state; users should keep Accessibility disabled if they want OCR/snapshot-only operation.
- A non-local VLM endpoint receives screenshots and prompts. Use only for trusted self-hosted systems where that disclosure is acceptable.
- `screen.describe` cache entries can include raw screenshot pixels until pruned or deleted.
- A VLM can misread UI, OCR, charts, QR/barcodes, or prompt-injection text; keep deterministic Vision OCR/barcode tools as the baseline for high-confidence extraction.
