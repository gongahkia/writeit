# Live Meeting Mode Feasibility

Date: 2026-07-08
Status: Feasibility proposal only; no UI or runtime implementation in this document.

## Verdict

[Inference] Live meeting mode is feasible as an opt-in, visible, local-first evaluation track, but not as a v1 default and not as a hidden assistant. The lowest-risk path is not "join meetings" or "listen all day". It is "explicitly capture this session, summarize locally, and answer first-party screen questions while active state stays visible".

No live speech/model benchmark reports were found in `.dist/validation/`. Existing VLM reports are fake-provider smoke artifacts, so they do not verify real VLM latency or quality.

## Required Boundary

Live meeting mode must keep these constraints:

- Explicit start/stop.
- Visible menu bar active state and, if an overlay exists, visible-to-user active state.
- Consent prompt before meeting or third-party conversation capture when consent is unclear.
- Local SpeechAnalyzer transcription as the first path.
- Screen context from read-only tools only.
- Optional `screen.describe` only through a configured local or explicitly allowed endpoint.
- Encrypted transcript storage only when user enables retention.
- No hidden overlay.
- No not-captured overlay.
- No screen-share bypass.
- No interview, exam, proctoring, assessment, or covert meeting coaching.
- No app control, browser navigation, shell execution, file search, MCP calls, or data mutation.

## Architecture Sketch

```text
explicit meeting-mode start
  -> permissions + consent gate
  -> visible active state in menu bar / approved overlay
  -> microphone stream
       AVAudioEngine -> SpeechAnalyzer -> SpeechTranscriber
  -> rolling local transcript buffer
       latest utterances + timestamps + confidence/quality flags
  -> screen context sampler
       ScreenCaptureKit screenshot
       Vision OCR
       Accessibility UI geometry
       optional passive screen.describe local VLM
  -> context packer
       consent state
       active app/window metadata
       recent transcript slice
       OCR/UI/VLM snippets
       audit boundary text
  -> Foundation Models session
       concise answer
       running notes
       action-item candidates
       refusal when request crosses policy
  -> output
       visible answer/notes
       optional AirPods speech
       encrypted transcript/audit if enabled
```

## Local Pipeline

1. Start
   - User starts meeting mode from the menu bar, hotkey, or configured AirPods gesture.
   - App checks Microphone, Speech Recognition, Screen Recording, Accessibility, and Input Monitoring as required by enabled features.
   - If the request involves other participants and consent is unclear, ask one concise consent question before capture.

2. Transcribe
   - Use the existing `Transcriber` path: `AVAudioEngine` tap, `SpeechAnalyzer`, `SpeechTranscriber`, asset installation, volatile results, and finalization.
   - Keep a rolling local buffer by default; persist only if transcript history or meeting notes are enabled.
   - Track first update latency, finalization duration, update count, final update count, and word error rate when expected text is available.

3. Read screen
   - Use `screen.ocr`, `screen.ui_elements`, `screen.barcodes`, and `screen.snapshot` for deterministic local context.
   - Use `screen.describe` only when `local-vlm.json` enables a provider and the user accepts screenshot handling.
   - Keep passive VQA only; no GUI-agent instructions or action plans.

4. Answer or note
   - For live answers, keep prompts short and grounded in recent transcript plus current screen context.
   - For notes, append locally generated bullets with timestamps and visible source boundaries.
   - Refuse hidden assistance, undisclosed meeting capture, interview coaching, exam help, proctoring bypass, or screen-share hiding.

5. Stop
   - Stop microphone, end screen sampling, finalize the transcript buffer, write audit entries, and show retention/delete choices if notes were enabled.

## Latency Estimate

These are feasibility targets, not measured results.

| Segment | Existing measurement path | Target for live answer | Notes |
| --- | --- | --- | --- |
| Speech first update | `Scripts/benchmark_speech.sh` | [Inference] <= 1.5s | AirPods/noisy room must be measured separately. |
| Speech finalization after stop | `Scripts/benchmark_speech.sh` | [Inference] <= 1.0s | Push-to-talk can tolerate finalization; open mic notes need rolling partials. |
| OCR/UI screen context | `Scripts/benchmark_model.sh --native-read-only-tools` plus tool logs | [Inference] <= 1.5s | OCR should be the default screen path. |
| Optional VLM context | `Scripts/benchmark_vlm.sh` | [Inference] <= 6.0s | Use only for questions OCR/UI cannot answer. |
| Foundation Models plan + answer | `Scripts/benchmark_model.sh` | [Inference] <= 3.0s | Prewarm before active session. |
| Total push-to-answer, OCR path | combined harness below | [Inference] <= 6.0s | Target includes speech stop/finalize, screen read, and answer. |
| Total push-to-answer, VLM path | combined harness below | [Inference] <= 10.0s | VLM path is fallback only. |
| Post-session note summary | model benchmark plus transcript payload | [Inference] <= 30.0s | Acceptable after stop; not a live answer target. |

## Model And Provider Requirements

Foundation Models:

- Required for local text planning, answer drafting, and note summarization.
- Must use read-only tool calls only.
- Must receive transcript/screen snippets as untrusted context.
- Should be prewarmed when meeting mode starts.

Speech:

- Required: `SpeechAnalyzer` and `SpeechTranscriber` on macOS 26.
- Required metrics: first update latency, finalization duration, word error rate, update count, and error states.
- AirPods must be validated as an input route; Mac mic fallback needs visible confirmation.

Screen:

- Required baseline: ScreenCaptureKit screenshots, Vision OCR/barcodes, Accessibility UI geometry.
- Optional: local VLM provider for passive `screen.describe`.
- Non-local VLM endpoints require explicit `allowNonLocalEndpoint` and screenshot-egress disclosure.

Storage:

- Default: ephemeral rolling buffer.
- Optional: encrypted local transcript and meeting-note retention.
- Required controls before persistence: export, delete session, delete all, retention limit, audit log.

## Permissions, Consent, And UI Disclosure

Permissions:

- Microphone: live speech capture.
- Speech Recognition: SpeechAnalyzer/SpeechTranscriber.
- Screen Recording: screenshot/OCR/VLM context.
- Accessibility: UI geometry.
- Input Monitoring: global hotkeys and hardware triggers.

Consent requirements:

- Ask before recording or summarizing meetings unless participant awareness is already clear.
- Refuse if the user asks to record or summarize a meeting without telling participants.
- Refuse live interview, exam, proctoring, hiring-screen, or assessment help when assistance is hidden or rule-bypassing.
- Keep consent state in the session audit.

UI disclosure requirements:

- Menu bar active state remains visible for microphone and screen reads.
- Overlay, if later approved, must be visible to the user and captured by normal screen sharing.
- No hidden/not-captured overlay requirement.
- Show local/remote VLM endpoint state before screenshot egress.
- Provide one-step stop/cancel in every active state.

## Benchmark Plan

Create one dated run directory per machine:

```text
.dist/validation/meeting-mode-YYYYMMDD-HHMM/
  speech-quiet.json
  speech-airpods-quiet.json
  speech-airpods-noisy.json
  model-loop.json
  model-native-tools.json
  vlm-generated.json
  vlm-golden.json
  meeting-combined.md
```

Run speech:

```sh
Scripts/benchmark_speech.sh --seconds 8 --expected "summarize the last point and read the visible slide title" --output .dist/validation/meeting-mode-YYYYMMDD-HHMM/speech-quiet.json
```

Run model loop:

```sh
Scripts/benchmark_model.sh --request "summarize the recent transcript and visible screen in one sentence" --iterations 5 --output .dist/validation/meeting-mode-YYYYMMDD-HHMM/model-loop.json
Scripts/benchmark_model.sh --native-read-only-tools --request "what text is visible on my screen?" --iterations 5 --output .dist/validation/meeting-mode-YYYYMMDD-HHMM/model-native-tools.json
```

Run VLM only if a local provider is configured:

```sh
Scripts/benchmark_vlm.sh --generated-fixture --output .dist/validation/meeting-mode-YYYYMMDD-HHMM/vlm-generated.json
Scripts/benchmark_vlm.sh --golden-fixtures Fixtures/VLM/golden-fixtures.json --output .dist/validation/meeting-mode-YYYYMMDD-HHMM/vlm-golden.json
```

Manual combined test:

```text
1. Start visible meeting mode.
2. Confirm consent prompt path.
3. Speak one test phrase through Mac mic.
4. Repeat through AirPods in quiet and noisy rooms.
5. Ask one OCR-only screen question.
6. Ask one VLM-needed screen question if local VLM is configured.
7. Stop session.
8. Verify transcript retention/delete/export behavior.
9. Verify menu bar and overlay visibility in screen recording.
10. Record total time from trigger to answer for each run.
```

Pass criteria before implementation:

- Speech first update, finalization, and WER meet targets on target hardware.
- OCR path meets push-to-answer target.
- VLM path either meets fallback target or stays disabled by default.
- Consent/refusal fixtures pass for meetings, interviews, exams, proctoring, and hidden capture.
- Screen-share recording shows active state; no not-captured overlay behavior.
- VoiceOver and keyboard checks pass for all active states.

## Product Recommendation

[Inference] Do not ship live meeting mode as a core v1 feature. Ship screen Q&A first, then run this benchmark plan. If the data passes, implement a constrained "Session Notes" experiment: explicit start/stop, visible state, consent gate, local transcript, OCR-first screen context, optional local VLM, and delete/export controls.

## Sources Checked

- `Docs/product-principles.md`
- `Docs/consent-and-misuse-policy.md`
- `Docs/meeting-notetaker-market-map.md`
- `Docs/real-time-assistant-market-map.md`
- `Docs/voice-dictation-market-map.md`
- `Docs/local-vision-models.md`
- `Docs/speech-benchmark.md`
- `Docs/model-benchmark.md`
- `Docs/vlm-benchmark.md`
- `Docs/transparent-overlay-ux-proposal.md`
- Apple SpeechAnalyzer: https://developer.apple.com/documentation/speech/speechanalyzer
- Apple SpeechTranscriber: https://developer.apple.com/documentation/speech/speechtranscriber
- Apple Speech live transcription guide: https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app
- Apple ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit/
- Apple SCContentSharingPicker: https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker
- Apple Foundation Models: https://developer.apple.com/documentation/foundationmodels
- Apple Foundation Models tool calling: https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling
- Apple Foundation Models runtime performance: https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app
