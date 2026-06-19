# Threat Model Notes

## Prompt Injection

Tool outputs, MCP payloads, OCR text, web results, file names, mail metadata, and shell output can contain hostile instructions. The app wraps tool payloads as untrusted blocks and escapes matching closing delimiters before model ingress. New tool families must keep payload data separate from system/developer instructions.

## Tool Misuse

The primary misuse risk is a model plan that invokes an unintended tool or mutating action. Mitigations are read-default tool exposure, per-session ambient allowlists, `mutatesState` metadata, confirmation-gated mutating tools, default-off shell/MCP execution surfaces, and command revalidation inside `ShellExecService.xpc`.

## Local Data Storage

The primary local data risks are plaintext transcripts, plaintext memory, tampered audit entries, and unbounded screen snapshots. Mitigations are AES-GCM encrypted transcript/memory stores, Keychain-backed keys, HMAC-signed audit hash chains, app-owned path tests, cache retention for screen snapshots, and rollback instructions for deleting app data and Keychain entries.

## Residual Risks

- A user can approve a risky action after misleading context; confirmation copy must stay explicit.
- Apple Events depend on target app behavior and system Automation prompts.
- MCP servers are external trust boundaries and should be enabled only for trusted configs.
- Local manifest tools are an extension boundary; they can only wrap allowlisted shell commands and still require confirmation.
- Screen snapshots may include sensitive visible content until cache pruning or user deletion.
