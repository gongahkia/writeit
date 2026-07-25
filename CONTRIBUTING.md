# Contributing

## Prerequisites

- macOS Tahoe 26 or later
- Xcode 26 or later
- Swift Package Manager from the active Xcode toolchain
- Apple Silicon Mac with Apple Intelligence enabled for Foundation Models validation
- AirPods with headphone motion support for AirPods trigger and routing validation
- Developer ID Application certificate and `notarytool` profile for release packaging work

Use `xcode-select -p` to confirm the active Xcode before building.

## Setup

```sh
swift package resolve
swift test
```

Build a local ad-hoc app bundle:

```sh
Scripts/build_app.sh
```

## Development Rules

- Keep changes scoped to the requested behavior.
- Keep default tool behavior read-only unless a user confirmation gate is explicit.
- Treat transcript, memory, audit, Keychain, MCP OAuth, screen capture, calendar, reminders, mail, and shell paths as security-sensitive.
- Do not commit `.build/`, `.dist/`, app bundles, videos, zips, private recordings, local validation outputs, credentials, or generated adapters.
- Run `Scripts/open_source_check.sh secrets` before sharing changes that touched scripts, docs, config, or release paths.

## Validation

Run the narrowest relevant checks first, then `swift test` before opening a pull request.

Use `Docs/macos-validation.md` for manual target-hardware validation. If hardware is unavailable, mark the validation gap in the pull request.

For release packaging changes, run the relevant scripts:

```sh
Scripts/build_app.sh
Scripts/release_check.sh dev-id
Scripts/release_check.sh notary
Scripts/release_check.sh demo
Scripts/release_check.sh oss
```

For a full signed release smoke test:

```sh
CODESIGN_IDENTITY="Developer ID Application: Team Name (TEAMID)" \
NOTARY_PROFILE=cerberus-notary \
Scripts/release_smoke.sh
```

## Pull Requests

Include:

- what changed
- tests or checks run
- release-check impact
- permission/privacy impact
- target-hardware validation status
- rollback notes when app data, Keychain, permissions, signing, or launch artifacts change
