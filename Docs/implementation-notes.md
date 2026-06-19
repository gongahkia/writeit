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
- Earcons are mapped from the triggering state-machine event, so same-destination transitions such as cancel vs finished and approval vs execution start are audibly distinct.
- The menu bar extra uses a custom SwiftUI label so active microphone states can tint the status icon red.
- First launch opens the Access panel while required permissions remain ungranted, with skip and reset controls persisted in UserDefaults.
- Calendar and Reminders permission prompts include full-access usage descriptions; write-only EventKit access is displayed separately because read tools require full access.
- AirPods gesture validation can be logged to `~/Library/Application Support/cerberus/head-gesture-validation.csv`; `Scripts/evaluate_head_gestures.sh` summarizes quiet motion, detections, and conservative threshold suggestions.
- `Scripts/benchmark_speech.sh` runs the app's SpeechAnalyzer transcription path against the current macOS input device and reports latency plus optional word error rate.
- `Wake phrase` is default-off. It can use SpeechAnalyzer phrase matching or an optional SoundAnalysis/Core ML sound classifier configured in `~/Library/Application Support/cerberus/wake-word-sound-classifier.json`.
- `Scripts/record_wake_samples.sh` records labeled mono 16 kHz WAV files plus `manifest.jsonl`; `Scripts/train_wake_word_model.sh` trains a local CreateML sound classifier and can write the app config.
- Listening auto-runs after a 1.5 second transcript silence timeout.
- Spoken replies use `AVSpeechSynthesizer`; by default they follow the current macOS output device, and Settings can opt into direct AirPods playback by rendering speech buffers through an `AVAudioEngine` output unit pinned to the detected AirPods output device.
- A stem triple-press while speaking interrupts the current reply and starts a new listening turn.
- Read-only tools are exposed through FoundationModels native `Tool` adapters; mutating tools stay on guided planning and explicit confirmation.
- FoundationModels native tool adapters fail closed if asked to execute a mutating tool.
- `Scripts/benchmark_model.sh` measures Foundation Models planning and tool-output summarization latency, with optional native read-only tool-session timing.
- Planning context includes the current `NSWorkspace.frontmostApplication` localized name when available.
- Planning context includes bounded project/workspace hints detected from approved file-search folders using markers such as `Package.swift`, `.xcworkspace`, `.xcodeproj`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, and `.git`.
- Planning context includes per-app policy hints for Xcode, Terminal, Finder, Safari, Chrome, Calendar, Mail, and Music, constrained to currently enabled tools.
- `files.search` is constrained to user-approved folders selected in Settings; omitted `scopePath` searches all approved folders, while explicit scopes must be inside an approved folder.
- Settings includes a default-on local-only Foundation Models lock. Current default and adapter profiles pass it; future profile names containing cloud, remote, server, non-local, or PCC markers are blocked before session update.
- Settings exposes a per-session allowlist for ambient tools; disabled tools are omitted from the planner prompt and execution allowlist.
- App-owned fallback still summarizes tool payloads through a second Foundation Models prompt before speech.
- Mutating plans can be confirmed by button, nod/shake, or short voice yes/no phrases.
- `calendar.create` is separate from `calendar.read`, mutates state, and is blocked by confirmation unless approved.
- `calendar.edit` and `calendar.delete` operate on one matching event and are blocked by confirmation unless approved.
- `reminders.create` is separate from `reminders.read`, mutates state, and is blocked by confirmation unless approved.
- `reminders.complete` marks one matching open reminder complete and is blocked by confirmation unless approved.
- `reminders.edit` and `reminders.delete` operate on one matching reminder and are blocked by confirmation unless approved.
- `contacts.search` is read-only and searches local Contacts by name, organization, email, or phone number after Contacts permission is granted.
- `notes.search` is read-only and searches Notes.app note title/body text through Apple Events.
- Audit logs are hash-chained and HMAC-signed at `~/Library/Application Support/cerberus/audit.log`.
- The panel shows the last 5 audit entries and answers "what did cerberus just do?" from the audit log.
- Transcripts are AES-GCM encrypted at `~/Library/Application Support/cerberus/transcripts.jsonl.enc` with a Keychain-stored key.
- Memory records are AES-GCM encrypted at `~/Library/Application Support/cerberus/memory.jsonl.enc` with a separate Keychain-stored key.
- App-owned default write paths are centralized under `~/Library/Application Support/cerberus/` or `~/Library/Caches/cerberus/`.
- `mail.search` reads Mail.app messages through Apple Events and is limited to subject/sender search unless body snippets are explicitly requested.
- `music.now_playing` reads Music.app state, while `music.control` is separate, mutates playback state, and is blocked by confirmation unless approved.
- `screen.snapshot` captures the main display through ScreenCaptureKit and writes a local PNG in `~/Library/Caches/cerberus/screen-snapshots/`.
- `screen.ocr` captures the main display through ScreenCaptureKit and runs local Vision OCR with confidence plus normalized and pixel bounding boxes. The checked Vision headers expose request-level language configuration/detection, but not a reliable per-result recognized-language field. The checked macOS FoundationModels swiftinterface exposes text `PromptRepresentable` input, not CGImage prompt input, so screen reasoning remains OCR/file-based instead of full visual reasoning.
- `mcp.call`, `mcp.resources.list`, `mcp.resource.read`, `mcp.prompts.list`, `mcp.prompt.get`, and MCP OAuth helpers are default-off and support configured MCP stdio or Streamable HTTP servers. Configured MCP `nativeReadOnlyTools` are also exposed to FoundationModels as dynamic read-only native tools for flat primitive JSON-object schemas.
- Tool, MCP, and nested MCP prompt payloads are wrapped as untrusted prompt blocks, and matching closing delimiters inside payload text are neutralized before model ingress.
- A prebuilt FoundationModels adapter can be loaded from `~/Library/Application Support/cerberus/foundation-model-adapter.json`.
- `shell.run` is default-off in the app, requires confirmation when enabled, and routes live commands through `ShellExecService.xpc`.

## Current Platform Assumptions

- FoundationModels reference re-check on 2026-06-19 used Xcode's `MacOSX26.5.sdk` plus the arm64e macOS swiftinterface at `MacOSX.sdk/System/Library/Frameworks/FoundationModels.framework/Versions/A/Modules/FoundationModels.swiftmodule/arm64e-apple-macos.swiftinterface` (`ff2285670b0966addb9827dc895a3ee3c9db6e186baae62c034fed012632aacc`, 1501 lines). The interface exposes `SystemLanguageModel.Availability`, `LanguageModelSession`, `PromptRepresentable`, `Tool`, `DynamicGenerationSchema`, token counting, and `SystemLanguageModel.Adapter` loading/compilation APIs; a symbol scan did not find public `CGImage`, `NSImage`, or image prompt input APIs in that macOS interface.
- Apple Foundation Models docs were re-checked on 2026-06-19 at `https://developer.apple.com/documentation/foundationmodels/` and `https://developer.apple.com/documentation/updates/foundationmodels`. The static responses require JavaScript; Apple search snippets still describe Foundation Models tool calling and updated Foundation Models Instruments, with no verified doc evidence changing the current OCR-first screen approach.
- Private Cloud Compute was re-checked on 2026-06-19 against Apple's WWDC26 session `https://developer.apple.com/videos/play/wwdc2026/319/`, `https://developer.apple.com/private-cloud-compute/`, and `https://developer.apple.com/apple-intelligence/whats-new/`. Apple now documents `PrivateCloudComputeLanguageModel()` as a one-line model swap for `LanguageModelSession`, with structured output and tool calling using the same Foundation Models API. PCC requires Apple Intelligence availability, internet connectivity, user quota handling, eligible developer/app status, and the Private Cloud Compute entitlement. cerberus keeps the local-only lock default-on and does not add a PCC path until the product privacy scope changes.
- Dynamic model profile APIs were re-checked on 2026-06-19. Apple search snippets mention `LanguageModelSession.Profile`/`DynamicProfile`, but the installed macOS 26.5 FoundationModels swiftinterface (`ff2285670b0966addb9827dc895a3ee3c9db6e186baae62c034fed012632aacc`, 1501 lines) does not expose `Profile` or `DynamicProfile`; it exposes `SystemLanguageModel(useCase:guardrails:)` with `.general` and `.contentTagging`, adapter-backed `SystemLanguageModel(adapter:guardrails:)`, and per-response `GenerationOptions` for sampling, temperature, and maximum response tokens.
- Apple search results on 2026-06-19 show newer Foundation Models image attachment docs (`Attachment`, `ImageAttachmentContent`, and multimodal prompting), but the installed macOS 26.5 SDK swiftinterface and prebuilt module do not expose `Attachment`, `ImageAttachmentContent`, `CGImage`, `CIImage`, `CVPixelBuffer`, or image URL prompt symbols. The installed Vision SDK exposes `VNRecognizeTextRequest` and `VNDetectBarcodesRequest`; exact SDK searches for `OCRTool` and `BarcodeReaderTool` returned zero matches.
- `SystemLanguageModel.Adapter` docs were re-checked on 2026-06-19. Apple's adapter type page requires JavaScript but search snippets and the installed swiftinterface agree on runtime APIs: `init(fileURL:)`, `init(name:)`, `compile()`, `compatibleAdapterIdentifiers(name:)`, `removeObsoleteAdapters()`, metadata, and `AssetError`. Apple's adapter training page documents a separate Python toolkit that exports `.fmadapter` packages and Background Assets bundles; no local Swift training API is exposed in the installed SDK.
- `SpeechAnalyzer` docs were re-checked on 2026-06-19. Apple's docs require JavaScript, but search snippets state it manages analysis sessions with speech modules and that `AssetInventory` installs required module assets before use. The installed Speech swiftinterface exposes `SpeechAnalyzer(modules:)`, `start(inputSequence:)`, `analyzeSequence(_:)`, `finalizeAndFinishThroughEndOfInput()`, `cancelAndFinishNow()`, and `bestAvailableAudioFormat(compatibleWith:)`, matching the current `Transcriber` stream/finalize/cancel path.
- `SpeechTranscriber` docs were re-checked on 2026-06-19. Apple's docs require JavaScript, but search snippets show `supportedLocale(equivalentTo:)`, presets, `volatileResults`, and `audioTimeRange`. The installed Speech swiftinterface (`9de012f407197106cef4b95f0e5d0d3c487a1a46f733db2aa488c6b77ecfbce6`, 682 lines) exposes locale support checks, `SpeechTranscriber(locale:transcriptionOptions:reportingOptions:attributeOptions:)`, `results` as an async sequence, `Result.text`, and `SpeechModuleResult.isFinal`, matching the current live transcript path.
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
