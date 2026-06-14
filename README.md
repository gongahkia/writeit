# cerberus

AirPods-driven, local-first personal assistant for macOS.

The project is intentionally scoped as a native macOS utility:

- menu bar first, no main window by default
- microphone activates only after an explicit trigger
- SpeechAnalyzer for on-device speech-to-text
- Foundation Models for on-device planning and typed tool calls
- tool implementations are audited, read-default, and confirmation-gated for risky actions
- shell execution is isolated behind an allowlist and intended to move into a sandboxed XPC service

## Requirements

- macOS Tahoe 26 or later
- Xcode 26 or later
- Apple Silicon Mac with Apple Intelligence enabled
- AirPods with headphone motion support for nod/shake triggers
- Microphone, Speech Recognition, Calendar, Reminders, Accessibility, and Input Monitoring permissions as features are enabled

This repository currently uses Swift Package Manager for source organization. Shipping as a notarized `.app` will require an Xcode app target or equivalent packaging step that applies `Config/cerberus.entitlements`.

## Development Notes

The Linux workspace used by Codex does not include Swift or Apple's macOS SDK, so compile validation must happen on a Mac with Xcode 26. Local checks here are limited to repository structure, text validation, and git history.

See `Docs/macos-validation.md` for the current validation checklist.
