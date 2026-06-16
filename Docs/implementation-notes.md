# Implementation Notes

These notes capture the current interpretation of `IDEA.md` so implementation choices stay explicit.

## Product Shape

cerberus is a hands-free macOS assistant shell, not a general chatbot. The model should plan, summarize, classify, and choose typed tools. Real work should happen in audited tools that interact with macOS state.

## MVP Order

1. Build the menu bar app and state machine.
2. Add deterministic triggers, starting with a manual menu trigger and then AirPods motion/media-key triggers.
3. Add speech input and spoken output.
4. Add Foundation Models planning.
5. Add a small, read-default tool surface.
6. Add confirmation, audit logs, and shell isolation before enabling mutating tools.

## Current Implementation

- SwiftPM builds `cerberus`, `CerberusCore`, and `ShellExecService`.
- `cerberus` has manual, Control-Option-Space, AirPods motion, and media-key trigger paths.
- `Wake phrase` is a default-off SpeechAnalyzer phrase monitor for "hey cerberus"; it is not a dedicated keyword-spotting model.
- Listening auto-runs after a 1.5 second transcript silence timeout.
- Read-only tools are exposed through FoundationModels native `Tool` adapters; mutating tools stay on guided planning and explicit confirmation.
- App-owned fallback still summarizes tool payloads through a second Foundation Models prompt before speech.
- Mutating plans can be confirmed by button, nod/shake, or short voice yes/no phrases.
- Audit logs are hash-chained at `~/Library/Application Support/cerberus/audit.log`.
- Transcripts are AES-GCM encrypted at `~/Library/Application Support/cerberus/transcripts.jsonl.enc` with a Keychain-stored key.
- Memory records are AES-GCM encrypted at `~/Library/Application Support/cerberus/memory.jsonl.enc` with a separate Keychain-stored key.
- `screen.ocr` captures the main display through ScreenCaptureKit and runs local Vision OCR. FoundationModels is text-only in this SDK, so this covers screen text, not full visual reasoning.
- `mcp.call` is default-off, confirmation-gated, and supports configured local MCP stdio servers via `initialize`, `tools/list`, and `tools/call`.
- A prebuilt FoundationModels adapter can be loaded from `~/Library/Application Support/cerberus/foundation-model-adapter.json`.
- `shell.run` is default-off in the app, requires confirmation when enabled, and routes live commands through `ShellExecService.xpc`.

## Current Platform Assumptions

- Foundation Models supports on-device sessions, guided generation, and tool calling on Apple Intelligence-capable systems.
- SpeechAnalyzer and SpeechTranscriber are macOS 26 APIs for live and recorded transcription.
- CMHeadphoneMotionManager can stream AirPods motion on macOS for supported headphones.
- AirPods head gestures are also used by Siri/system features, so custom nod detection needs real-device false-positive testing after neutral-pose calibration.
- Stem press interception is best treated as experimental because it overlaps with media controls.
- Wake phrase uses live speech transcription, not a dedicated low-power keyword-spotting model.
- FoundationModels native `Tool` protocol integration is intentionally read-only; mutating native tools would need a confirmation-aware tool protocol design.
- MCP support is a minimal stdio bridge; Streamable HTTP, resources, prompts, sampling, and dynamic native tool schemas are not implemented.
- I cannot verify a local FoundationModels adapter training API in this SDK; only adapter loading/compilation is wired.
