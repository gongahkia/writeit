# cerberus

AirPods-driven, local-first personal assistant for macOS.

The project is intentionally scoped as a native macOS utility:

- menu bar first, no main window by default
- first-run setup banner for required macOS permissions
- microphone activates only after an explicit trigger unless `Wake phrase` is enabled
- menu bar status icon tints red while the microphone is active
- SpeechAnalyzer for on-device speech-to-text
- live SpeechAnalyzer benchmark CLI for AirPods/noisy-room checks
- default-off wake phrase monitor with SpeechAnalyzer fallback or a configured SoundAnalysis/Core ML wake model
- wake-word WAV sample collector and CreateML trainer for local classifier training data
- speech replies can follow the current macOS output route or route directly to detected AirPods
- Foundation Models for on-device planning and native read-only typed tool calls
- Foundation Models latency benchmark CLI for plan/tool-loop checks
- active macOS application context is included in planning prompts
- optional AirPods gesture validation CSV logging for threshold tuning
- head gesture CSV evaluator for threshold tuning after real-device walks/tests
- per-session tool allowlist settings for the ambient tool surface
- file search is limited to Settings-approved folders
- tool implementations are audited, read-default, and confirmation-gated for risky actions
- calendar event creation is a separate mutating tool and requires confirmation
- reminder creation is a separate mutating tool and requires confirmation
- reminder completion is a separate mutating tool and requires confirmation
- encrypted local transcripts and memory records
- read-only Mail.app subject/sender search through macOS Automation
- Music.app now-playing reads and confirmation-gated playback controls
- local screen snapshots plus text OCR with bounding boxes for "what is on my screen?" requests
- default-off MCP bridge for configured stdio or Streamable HTTP servers, including OAuth PKCE browser handoff
- optional prebuilt FoundationModels adapter loading plus transcript JSONL export/eval and Apple toolkit orchestration
- shell execution is default-off, confirmation-gated, and routed through an allowlisted XPC service when enabled

## Requirements

- macOS Tahoe 26 or later
- Xcode 26 or later
- Apple Silicon Mac with Apple Intelligence enabled
- AirPods with headphone motion support for nod/shake triggers
- Microphone, Speech Recognition, Calendar, Reminders, Accessibility, Input Monitoring, and Screen Recording permissions as features are enabled

This repository uses Swift Package Manager for source organization. `Scripts/build_app.sh` assembles `.dist/cerberus.app`, applies `Config/cerberus.entitlements`, and embeds `ShellExecService` in `Contents/XPCServices`.
`Scripts/release_check.sh` verifies Developer ID signing, notarization, demo-video, and open-source release gates.

## Privacy

Planning, speech transcription, OCR, transcripts, memory, audit logs, wake samples, adapter config, MCP config, and screen snapshots are local by default. Transcripts and memory records are encrypted with Keychain-backed AES-GCM keys; audit entries are hash-chained and HMAC-signed.

Tool egress happens only through the tool the user enables or requests: Apple Events for Mail/Music/app control, EventKit for Calendar/Reminders, approved folders for file search, configured MCP servers, allowlisted web domains, and the default-off shell XPC service. Mutating built-in tools and `mcp.call` require confirmation before execution.

## Permissions

- Accessibility: opens the Access panel and supports app-control workflows.
- Input Monitoring: supports global trigger keys and media-key handling.
- Microphone: records voice requests, wake phrase monitoring, and speech benchmarks.
- Speech Recognition: runs SpeechAnalyzer/SpeechTranscriber transcription.
- Calendar: reads events and creates events after confirmation.
- Reminders: reads reminders and creates/completes reminders after confirmation.
- Screen Recording: captures local screen snapshots and OCR text boxes.
- Automation: talks to Mail, Music, and app-control targets through Apple Events.
- Network Client: contacts allowlisted web search endpoints and configured MCP HTTP/OAuth servers.

## Development Notes

Primary validation is `swift test` on macOS with Xcode 26.
Run `Scripts/lint_scripts.sh` before editing release or validation shell scripts.
Run `Scripts/static_grep_check.sh` before publishing or uploading logs.

See `Docs/macos-validation.md` for the current validation checklist.
See `Docs/mcp.md` for the MCP stdio config format.
See `Docs/adapters.md` for optional FoundationModels adapter loading.
See `Docs/model-benchmark.md` for Foundation Models planning/tool-loop latency checks.
See `Docs/speech-benchmark.md` for live SpeechAnalyzer benchmark runs.
See `Docs/request-examples.md` for read-only, confirmation-gated, and refused request examples.
See `Docs/airpods.md` for AirPods motion troubleshooting.
See `Docs/troubleshooting.md` for Foundation Models, SpeechAnalyzer, permissions, MCP OAuth, and shell XPC recovery.
See `Docs/wake-word.md` for optional SoundAnalysis/Core ML wake model setup.
See `Docs/distribution.md` for local app packaging, demo recording, and notarization.
See `Docs/architecture.md` for the current app/core/tool/service layout.
See `Docs/security-model.md` for trust boundaries, execution rules, and reviewer checks.
See `Docs/threat-model.md` for prompt-injection, tool-misuse, and local-storage threat notes.
See `Docs/open-source.md` for public repository release checks.
See `CONTRIBUTING.md` for local setup, validation, signing, and hardware prerequisites.
