# cerberus

AirPods-driven, local-first personal assistant for macOS.

The project is intentionally scoped as a native macOS utility:

- menu bar first, no main window by default
- microphone activates only after an explicit trigger unless `Wake phrase` is enabled
- SpeechAnalyzer for on-device speech-to-text
- default-off STT wake phrase monitor for "hey cerberus"
- Foundation Models for on-device planning and native read-only typed tool calls
- tool implementations are audited, read-default, and confirmation-gated for risky actions
- encrypted local transcripts and memory records
- local screen text OCR for "what text is on my screen?" requests
- default-off MCP stdio bridge for configured local MCP servers
- shell execution is default-off, confirmation-gated, and routed through an allowlisted XPC service when enabled

## Requirements

- macOS Tahoe 26 or later
- Xcode 26 or later
- Apple Silicon Mac with Apple Intelligence enabled
- AirPods with headphone motion support for nod/shake triggers
- Microphone, Speech Recognition, Calendar, Reminders, Accessibility, Input Monitoring, and Screen Recording permissions as features are enabled

This repository uses Swift Package Manager for source organization. `Scripts/build_app.sh` assembles `.dist/cerberus.app`, applies `Config/cerberus.entitlements`, and embeds `ShellExecService` in `Contents/XPCServices`.

## Development Notes

Primary validation is `swift test` on macOS with Xcode 26.

See `Docs/macos-validation.md` for the current validation checklist.
See `Docs/mcp.md` for the MCP stdio config format.
