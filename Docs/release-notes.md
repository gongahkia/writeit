# Release Notes

## v0.1.0 - draft

First tagged build target for cerberus, pending Developer ID signing, notarization, and target-hardware validation.

### Included

- menu bar macOS assistant shell for explicit listening, cancellation, setup, settings, transcript, and audit flows
- SpeechAnalyzer transcription path, live speech benchmark CLI, and optional wake phrase monitor
- AirPods motion trigger path with head-gesture validation logging and evaluator scripts
- Foundation Models planning path with native read-only tool adapter support and benchmark tooling
- confirmation-gated tool registry for mutating built-in tools
- encrypted local transcript and memory storage
- default-off shell execution routed through `ShellExecService.xpc`
- default-off MCP bridge for stdio and Streamable HTTP servers, including OAuth PKCE support
- local screen snapshot and OCR tool path
- adapter dataset export, evaluation, and training orchestration scripts
- release packaging, open-source readiness, demo recording, and release smoke scripts

### Release Gates

- Developer ID signing, notarization, Gatekeeper assessment, and package checksum validation must pass through `Scripts/release_smoke.sh`.
- Real macOS 26 hardware, Apple Intelligence availability, AirPods routing, and permission-denial flows remain mandatory validation before publishing.
- Repository license, visibility, and GitHub security settings must be finalized before public release.

### Rollback

Rollback steps must be finalized before the tag is cut.
