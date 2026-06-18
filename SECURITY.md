# Security Policy

## Supported Versions

Only the latest tagged release is supported for security fixes. Before the first public tag, report issues against `main` and include the commit hash tested.

## Reporting

Use GitHub private vulnerability reporting if it is enabled for the repository. If it is not enabled, contact the repository owner through GitHub and request a private security channel before sharing exploit details.

Do not include secrets, private transcripts, memory files, OAuth tokens, Keychain dumps, calendar data, reminder data, mail subjects, screen captures, or AirPods recordings in a public issue.

## Local Data

cerberus stores app-owned data under:

- `~/Library/Application Support/cerberus/`
- `~/Library/Caches/cerberus/`

Encrypted transcript and memory files use keys stored in Keychain service `dev.gongahkia.cerberus`. MCP OAuth tokens may also be stored in the same Keychain service.

When reporting a local-data issue, prefer redacted file names, command output, and reproduction steps. If a maintainer needs sample data, create synthetic data that does not contain real personal content.

## Security-Relevant Areas

Security reports are especially useful for:

- tool confirmation bypasses
- shell allowlist or XPC escape issues
- prompt injection that causes unintended tool execution
- leakage of transcript, memory, audit, OAuth, or Keychain material
- permission-denial paths that fail open
- MCP OAuth, token attachment, or authorization-header precedence bugs
- screen capture or OCR behavior that exceeds explicit user intent

## Local Cleanup

Use `Docs/rollback.md` to remove app data, Keychain items, permissions, and launch artifacts before retesting a fix.
