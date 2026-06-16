# macOS Validation Checklist

Validate the implementation on a Mac that matches the project requirements.

## Required Environment

- macOS Tahoe 26 or later
- Xcode 26 or later
- Apple Silicon Mac with Apple Intelligence enabled
- AirPods with headphone motion support for gesture tests

## Build Checks

1. Open the package in Xcode 26.
2. Confirm `Package.swift` resolves with the macOS 26 platform setting.
3. Run `swift test`.
4. Build the `cerberus` and `ShellExecService` executable products.
5. Check all warnings from Swift 6 concurrency and macOS availability annotations.

## Runtime Checks

1. Launch the menu bar app and confirm the status item appears without a main window.
2. Confirm first-run setup selects the Access panel while required permissions are missing; use `Skip` and `Reset setup` to confirm the persisted setup state.
3. Request Microphone, Speech Recognition, and Screen Recording permissions.
4. Press `Listen`, speak a short request, then wait 1.5 seconds or press `Run`.
5. Confirm SpeechAnalyzer transcribes into the request field and silence moves to reasoning.
6. Set a custom `Wake phrase`, enable it, say that phrase, and confirm the app starts active listening; then disable it and confirm the mic indicator clears.
7. Select AirPods as the macOS input device, run `Scripts/benchmark_speech.sh --seconds 8 --expected "hey cerberus open calendar"` in quiet and noisy conditions, and compare latency, transcript, and word error rate.
8. Run `Scripts/record_wake_samples.sh --label hey_cerberus --count 2 --seconds 1.0 --no-prompt` and confirm WAV files plus `manifest.jsonl` are written under `~/Library/Application Support/cerberus/wake-word-samples/`.
9. After collecting a two-class wake/background dataset, run `Scripts/train_wake_word_model.sh --target-label hey_cerberus --write-config` and confirm it writes `~/Library/Application Support/cerberus/wake-word-models/CerberusWakeWord.mlmodel` plus `wake-word-sound-classifier.json`.
10. Enable `Use sound wake model` and confirm matching model labels start listening; remove the config and confirm Settings reports fallback to speech phrase.
11. Confirm Control-Option-Space starts listening while the app is not focused.
12. Connect AirPods, set them as the macOS output device, and confirm Settings updates to the AirPods route before testing spoken replies; switch back to another output device and confirm the route updates again.
13. Enable `Route speech directly to AirPods`, leave another output device as system default, and confirm spoken replies still play through AirPods.
14. During a long spoken reply, triple-press the AirPods stem and confirm speech stops and a new listening turn starts.
15. Confirm Foundation Models returns either a direct spoken response or a typed tool plan.
16. Run `Scripts/benchmark_model.sh --request "what text is on my screen?" --iterations 3` and record plan plus synthetic tool-output latency.
17. Trigger a read-only tool request, such as "what is playing in Music?", "search my files for README", "search my mail for Apple", or "what text is on my screen?".
18. Confirm tool payloads are summarized into a useful spoken response.
19. Add `~/Library/Application Support/cerberus/foundation-model-adapter.json` with a valid prebuilt adapter and confirm startup reports `FoundationModels adapter loaded.`.
20. Confirm `~/Library/Application Support/cerberus/audit.log` records tool calls with a hash chain and per-entry signature.
21. Confirm the `Audit` panel shows the last 5 tool calls and "what did cerberus just do?" answers from the latest audit entry.
22. Confirm `~/Library/Application Support/cerberus/transcripts.jsonl.enc` is written and not plaintext.
23. Ask cerberus to remember a preference and confirm `~/Library/Application Support/cerberus/memory.jsonl.enc` is written and not plaintext.
24. Run `Scripts/export_adapter_dataset.sh /tmp/cerberus-adapter-data` and confirm it writes `train.jsonl` and `eval.jsonl` from encrypted transcript records.
25. Run `Scripts/evaluate_adapter_dataset.sh /tmp/cerberus-adapter-data/eval.jsonl --limit 5` and confirm it reports total, matches, and accuracy.
26. With Apple's adapter toolkit downloaded, run `ADAPTER_TOOLKIT_DIR=/path/to/toolkit DATA_DIR=/tmp/cerberus-adapter-data Scripts/train_adapter.sh` and confirm it writes an `.fmadapter` export.
27. Confirm `screen.snapshot` writes a PNG under `~/Library/Caches/cerberus/screen-snapshots/`, and `screen.ocr` emits local Vision text results with bounding boxes; both must fail closed when Screen Recording is denied.
28. Trigger a mutating plan, such as opening Calendar, and confirm the UI enters `awaiting_confirm`.
29. Confirm `Approve`, nod, or voice "yes" executes the tool; `Deny`, shake, stem press, or voice "no" cancels it.
30. Keep `MCP tool` and `Shell tool` disabled and confirm those requests are rejected as disabled.
31. Add `~/Library/Application Support/cerberus/mcp-servers.json`, enable `MCP tool`, and confirm an MCP `tools/call` request runs only after approval while resource/prompt/OAuth discovery reads run read-only.
32. With a stdio MCP server that sends `sampling/createMessage`, confirm the panel shows prompt review, then response review, before the MCP tool call completes.
33. With a stdio MCP server that sends `elicitation/create`, confirm the panel allows accept, decline, and cancel, and invalid accepted JSON fails closed.
34. With a Streamable HTTP MCP server that supports GET SSE, confirm enabling `MCP tool` starts the listener and routes server sampling/elicitation requests through the panel.
35. For an OAuth-protected Streamable HTTP MCP server, run `mcp.oauth.authorize.local`, complete the browser authorization, then run `mcp.oauth.refresh` if a refresh token was issued and confirm later MCP HTTP calls attach the stored bearer token.
36. Add a trusted read-only MCP tool name to `nativeReadOnlyTools`, enable `MCP tool`, and confirm a read-only answer can call it through FoundationModels native tool use without exposing mutating tools.
37. Enable `Shell tool`, request an allowlisted command such as `git status`, and confirm it routes through `ShellExecService.xpc` only after approval.
38. Enable `Log gesture validation CSV`, test AirPods nod, shake, and stem press behavior separately from speech/model behavior, then confirm `~/Library/Application Support/cerberus/head-gesture-validation.csv` contains pitch/yaw samples, neutral pose, deltas, and detected gestures.
39. Run `Scripts/evaluate_head_gestures.sh` and compare the suggested pitch/yaw thresholds against the Settings sliders after walking and stillness samples.
40. Confirm the first `mail.search` call prompts for Mail Automation access, then returns subject/sender metadata without changing read status.

## Known Follow-Up

- `Scripts/build_app.sh` embeds `ShellExecService.xpc`; Developer ID signing and notarization still require local credentials.
- SpeechAnalyzer and AirPods microphone quality can be measured with `Scripts/benchmark_speech.sh`; target-hardware quiet/walking/noisy results are not bundled.
- Foundation Models planning and tool-output loop latency can be measured with `Scripts/benchmark_model.sh`; target-hardware latency results are not bundled.
- AirPods nod/shake classification has manual neutral-pose calibration, adjustable thresholds, CSV validation logging, and an evaluator; thresholds still need real walking/noisy-environment data.
- Direct AirPods speech routing uses `AVSpeechSynthesizer.write` buffers plus `AVAudioEngine` output-unit device selection; it still needs real AirPods runtime validation on target hardware.
- Wake phrase can use a custom SoundAnalysis/Core ML classifier; sample collection and local CreateML training are supported, but no trained wake model is bundled.
- Native FoundationModels `Tool` integration is wired for read-only tools. Mutating tools remain on guided planning plus app-owned confirmation.
- Screen understanding captures PNG snapshots and OCR text boxes; full image prompting remains unavailable in the checked macOS FoundationModels swiftinterface.
- MCP support is limited to stdio and Streamable HTTP tools/resources/prompts plus OAuth PKCE browser handoff, localhost callback capture, refresh-token rotation, stdio or Streamable HTTP POST/GET-SSE sampling/elicitation review, GET SSE resume through `Last-Event-ID`, and opt-in native read-only tools for flat primitive schemas.
- Adapter training requires Apple's separate toolkit assets; prebuilt adapter loading, transcript-to-JSONL dataset export, exact-match eval, and toolkit orchestration are supported.
