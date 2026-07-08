# Implementation Notes

## Product Shape

cerberus is a hands-free macOS screen-reading assistant, not a computer operator. The model can answer directly or choose typed screen-reading tools. The shipped app must not click, type, open apps, navigate browsers, run commands, call MCP servers, or mutate user data.

## Current Implementation

- SwiftPM builds `cerberus` and `CerberusCore`.
- `cerberus` has manual, Control-Option-Space, AirPods motion, media-key, and optional wake-phrase trigger paths.
- The menu bar extra uses a custom SwiftUI label so active microphone states can tint the status icon red.
- First launch opens the Access panel while required permissions remain ungranted, with skip and reset controls persisted in UserDefaults.
- Required runtime permissions are Microphone, Speech Recognition, Accessibility, Input Monitoring, and Screen Recording.
- Listening auto-runs after a 1.5 second transcript silence timeout.
- Spoken replies use `AVSpeechSynthesizer`; Settings can opt into direct AirPods playback by rendering speech buffers through an `AVAudioEngine` output unit pinned to the detected AirPods output device.
- A stem triple-press while speaking interrupts the current reply and starts a new listening turn.
- The default tool catalog registers only `screen.snapshot`, `screen.ocr`, `screen.barcodes`, and `screen.ui_elements`.
- `screen.snapshot` captures the main display or active window through ScreenCaptureKit and writes a local PNG in `~/Library/Caches/cerberus/screen-snapshots/`.
- `screen.ocr` captures the main display or active window through ScreenCaptureKit and runs local Vision OCR with confidence plus normalized and pixel bounding boxes.
- `screen.barcodes` uses the same capture path with local Vision barcode/QR recognition, payload redaction, and normalized plus pixel boxes.
- `screen.ui_elements` reads active-app Accessibility roles, labels, and global screen frames.
- Screen tools fail closed when Screen Recording or Accessibility permission is denied.
- FoundationModels native tool adapters are wired only for screen-reading tools.
- Tool payloads are wrapped as untrusted prompt blocks, and matching closing delimiters inside payload text are neutralized before model ingress.
- Audit logs are hash-chained and HMAC-signed at `~/Library/Application Support/cerberus/audit.log`.
- The panel shows the last 5 audit entries and answers "what did cerberus just do?" from the audit log.
- Transcripts are AES-GCM encrypted at `~/Library/Application Support/cerberus/transcripts.jsonl.enc` with a Keychain-stored key.
- Screen snapshots are cache-pruned by age/count and can be opened or deleted from Settings.
- Settings exposes a per-session allowlist for screen tools; disabled tools are omitted from the planner prompt and execution allowlist.
- Settings includes a default-on local-only Foundation Models lock. Current default and adapter profiles pass it; future profile names containing cloud, remote, server, non-local, or PCC markers are blocked before session update.
- `Scripts/benchmark_model.sh` measures Foundation Models planning and tool-output summarization latency, with optional native screen-tool session timing.
- `Scripts/benchmark_speech.sh` runs the app's SpeechAnalyzer transcription path against the current macOS input device and reports latency plus optional word error rate.
- `Wake phrase` is default-off. It can use SpeechAnalyzer phrase matching or an optional SoundAnalysis/Core ML sound classifier configured in `~/Library/Application Support/cerberus/wake-word-sound-classifier.json`.
- `Scripts/record_wake_samples.sh` records labeled mono 16 kHz WAV files plus `manifest.jsonl`; `Scripts/train_wake_word_model.sh` trains a local CreateML sound classifier and can write the app config.
- AirPods gesture validation can be logged to `~/Library/Application Support/cerberus/head-gesture-validation.csv`; `Scripts/evaluate_head_gestures.sh` summarizes quiet motion, detections, and conservative threshold suggestions.
- A prebuilt FoundationModels adapter can be loaded from `~/Library/Application Support/cerberus/foundation-model-adapter.json`.

## Explicitly Not Shipped

- App control
- Browser tab reads or URL opens
- Calendar, Reminders, Contacts, Mail, Music, Finder, Shortcuts, file search, web search
- MCP calls/listeners/OAuth
- Shell commands, local command manifests, or XPC shell service embedding
- Stealth, hidden overlays, screen-share bypass, proctoring bypass, or interview-cheating workflows

## Current Platform Assumptions

- The checked macOS FoundationModels SDK exposes text prompt input and tool calling; full image prompt input remains unverified in this repo.
- Screen reasoning therefore uses local ScreenCaptureKit, Vision OCR/barcode extraction, and Accessibility UI metadata.
- Foundation Models supports on-device sessions, guided generation, and tool calling on Apple Intelligence-capable systems.
- Foundation Models latency is measurable through `Scripts/benchmark_model.sh`; target-hardware results are not bundled.
- SpeechAnalyzer and SpeechTranscriber are macOS 26 APIs for live and recorded transcription; AirPods/noisy-room quality is measured through the local benchmark script and still needs target-hardware runs.
- CMHeadphoneMotionManager can stream AirPods motion on macOS for supported headphones.
- AirPods head gestures are also used by Siri/system features, so custom nod detection still needs real-device false-positive testing with validation logs after neutral-pose calibration and threshold adjustment.
- Wake phrase has an optional custom SoundAnalysis/Core ML classifier path, a local sample collector, and a CreateML trainer; no trained wake model is bundled.
- I cannot verify a local FoundationModels adapter training API in this SDK; adapter loading/compilation, transcript-to-JSONL dataset export, exact-match eval, and Apple toolkit orchestration are wired.
- `AVSpeechSynthesizer` on macOS does not expose a direct per-device route selector in the checked SDK headers; direct AirPods mode works around that by using synthesized buffers and `kAudioOutputUnitProperty_CurrentDevice`.
