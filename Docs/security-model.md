# Security Model

## Trust Boundaries

- User input, speech transcripts, tool payloads, MCP data, web results, Mail/Music Apple Event output, file names, OCR text, and shell output are untrusted.
- `cerberusApp` is trusted to present state, collect confirmation, and route approved actions.
- `cerberusCore` is trusted to enforce tool allowlists, confirmation, storage encryption, prompt-boundary escaping, and audit signing.
- `ShellExecService.xpc` is a separate execution boundary for allowlisted shell commands.

## Execution Rules

- Read-only built-in tools can run without confirmation when enabled.
- Mutating built-in tools require confirmation through `ConfirmationGate`.
- `shell.run` is default-off, requires explicit Settings opt-in, requires confirmation, and revalidates commands in the XPC service.
- `mcp.call` is confirmation-gated. MCP resources, prompts, OAuth helpers, and trusted `nativeReadOnlyTools` are separate read paths.
- Disabled ambient tools are omitted from planning prompts and rejected by the execution allowlist.

## Storage Rules

- App-owned files live under `~/Library/Application Support/cerberus/` or `~/Library/Caches/cerberus/`.
- Transcripts and memory are AES-GCM encrypted with Keychain-stored keys.
- Audit logs are hash-chained and HMAC-signed with a Keychain-stored signing key.
- Screen snapshots are cached under `~/Library/Caches/cerberus/screen-snapshots/` and pruned by age/count.

## Review Checklist

- Confirm new tools declare `mutatesState` correctly.
- Confirm new model-ingress payloads use prompt-boundary escaping.
- Confirm new write paths use `CerberusDirectories`.
- Confirm new network/file/app egress is user-enabled, scoped, or confirmation-gated.
- Confirm release entitlements and `Info.plist` usage descriptions match shipped capabilities.
