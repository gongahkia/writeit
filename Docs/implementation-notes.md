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
- First launch opens the Access panel while required permissions remain ungranted, with skip and reset controls persisted in UserDefaults.
- AirPods gesture validation can be logged to `~/Library/Application Support/cerberus/head-gesture-validation.csv`; `Scripts/evaluate_head_gestures.sh` summarizes quiet motion, detections, and conservative threshold suggestions.
- `Scripts/benchmark_speech.sh` runs the app's SpeechAnalyzer transcription path against the current macOS input device and reports latency plus optional word error rate.
- `Wake phrase` is default-off. It can use SpeechAnalyzer phrase matching or an optional SoundAnalysis/Core ML sound classifier configured in `~/Library/Application Support/cerberus/wake-word-sound-classifier.json`.
- `Scripts/record_wake_samples.sh` records labeled mono 16 kHz WAV files plus `manifest.jsonl`; `Scripts/train_wake_word_model.sh` trains a local CreateML sound classifier and can write the app config.
- Listening auto-runs after a 1.5 second transcript silence timeout.
- Spoken replies use `AVSpeechSynthesizer`; by default they follow the current macOS output device, and Settings can opt into direct AirPods playback by rendering speech buffers through an `AVAudioEngine` output unit pinned to the detected AirPods output device.
- A stem triple-press while speaking interrupts the current reply and starts a new listening turn.
- Read-only tools are exposed through FoundationModels native `Tool` adapters; mutating tools stay on guided planning and explicit confirmation.
- `Scripts/benchmark_model.sh` measures Foundation Models planning and tool-output summarization latency, with optional native read-only tool-session timing.
- Explicit file search scopes must be existing directories inside the user's home directory.
- Settings exposes a per-session allowlist for ambient tools; disabled tools are omitted from the planner prompt and execution allowlist.
- App-owned fallback still summarizes tool payloads through a second Foundation Models prompt before speech.
- Mutating plans can be confirmed by button, nod/shake, or short voice yes/no phrases.
- `calendar.create` is separate from `calendar.read`, mutates state, and is blocked by confirmation unless approved.
- `reminders.create` is separate from `reminders.read`, mutates state, and is blocked by confirmation unless approved.
- `reminders.complete` marks one matching open reminder complete and is blocked by confirmation unless approved.
- Audit logs are hash-chained and HMAC-signed at `~/Library/Application Support/cerberus/audit.log`.
- The panel shows the last 5 audit entries and answers "what did cerberus just do?" from the audit log.
- Transcripts are AES-GCM encrypted at `~/Library/Application Support/cerberus/transcripts.jsonl.enc` with a Keychain-stored key.
- Memory records are AES-GCM encrypted at `~/Library/Application Support/cerberus/memory.jsonl.enc` with a separate Keychain-stored key.
- `mail.search` reads Mail.app messages through Apple Events and is limited to subject/sender search unless body snippets are explicitly requested.
- `screen.snapshot` captures the main display through ScreenCaptureKit and writes a local PNG in `~/Library/Caches/cerberus/screen-snapshots/`.
- `screen.ocr` captures the main display through ScreenCaptureKit and runs local Vision OCR with normalized and pixel bounding boxes. The checked macOS FoundationModels swiftinterface exposes text `PromptRepresentable` input, not CGImage prompt input, so screen reasoning remains OCR/file-based instead of full visual reasoning.
- `mcp.call`, `mcp.resources.list`, `mcp.resource.read`, `mcp.prompts.list`, `mcp.prompt.get`, and MCP OAuth helpers are default-off and support configured MCP stdio or Streamable HTTP servers. Configured MCP `nativeReadOnlyTools` are also exposed to FoundationModels as dynamic read-only native tools for flat primitive JSON-object schemas.
- A prebuilt FoundationModels adapter can be loaded from `~/Library/Application Support/cerberus/foundation-model-adapter.json`.
- `shell.run` is default-off in the app, requires confirmation when enabled, and routes live commands through `ShellExecService.xpc`.

## Current Platform Assumptions

- Foundation Models supports on-device sessions, guided generation, and tool calling on Apple Intelligence-capable systems.
- Foundation Models latency is measurable through `Scripts/benchmark_model.sh`; target-hardware results are not bundled.
- SpeechAnalyzer and SpeechTranscriber are macOS 26 APIs for live and recorded transcription; AirPods/noisy-room quality is measured through the local benchmark script and still needs target-hardware runs.
- CMHeadphoneMotionManager can stream AirPods motion on macOS for supported headphones.
- AirPods head gestures are also used by Siri/system features, so custom nod detection still needs real-device false-positive testing with validation logs after neutral-pose calibration and threshold adjustment.
- Stem press interception is best treated as experimental because it overlaps with media controls.
- Wake phrase has an optional custom SoundAnalysis/Core ML classifier path, a local sample collector, and a CreateML trainer; no trained wake model is bundled.
- FoundationModels native `Tool` protocol integration is intentionally read-only; mutating native tools would need a confirmation-aware tool protocol design.
- Full multimodal screen prompting is not wired because the checked macOS FoundationModels SDK does not expose a public image prompt API; `screen.snapshot` preserves the captured image locally for user review or future API support.
- MCP support covers stdio and Streamable HTTP tools, resources, prompts, OAuth PKCE browser handoff, localhost callback capture, refresh-token rotation, POST-SSE server requests, background Streamable HTTP GET listening, GET SSE resume through `Last-Event-ID`, and opt-in dynamic native read-only tool schemas for flat primitive inputs. Sampling/elicitation requests are routed through in-app review when MCP tools are enabled and otherwise fail closed with JSON-RPC errors.
- I cannot verify a local FoundationModels adapter training API in this SDK; adapter loading/compilation, transcript-to-JSONL dataset export, exact-match eval, and Apple toolkit orchestration are wired.
- `AVSpeechSynthesizer` on macOS does not expose a direct per-device route selector in the checked SDK headers; direct AirPods mode works around that by using synthesized buffers and `kAudioOutputUnitProperty_CurrentDevice`.
