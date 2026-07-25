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
4. Build the `cerberus` executable product.
5. Check all warnings from Swift 6 concurrency and macOS availability annotations.
6. Run `Scripts/build_app.sh --check`.
7. Run `Scripts/lint_scripts.sh`.
8. Run `Scripts/static_grep_check.sh`.

## Runtime Checks

1. Launch the menu bar app and confirm the status item appears without a main window.
2. Confirm first-run setup selects the Access panel while required permissions are missing; use relaunch, `Skip`, and `Reset setup` to confirm per-permission setup progress and persisted setup state.
3. Request Microphone, Speech Recognition, Accessibility, Input Monitoring, and Screen Recording permissions.
4. Deny Screen Recording in a clean account and confirm `screen.snapshot`, `screen.ocr`, and `screen.barcodes` fail closed.
5. Deny Accessibility in a clean account and confirm `screen.ui_elements` fails closed.
6. Press `Listen`, speak a short request, then wait 1.5 seconds or press `Run`.
7. Confirm the menu bar status item turns red while the microphone is active and clears when listening stops.
8. Confirm SpeechAnalyzer transcribes into the request field and silence moves to reasoning.
9. Ask "what text is on my screen?" and confirm `screen.ocr` is selected with no confirmation request.
10. Ask "capture what I am looking at" and confirm `screen.snapshot` writes a PNG under `~/Library/Caches/cerberus/screen-snapshots/`.
11. Ask "is there a QR code on screen?" and confirm `screen.barcodes` emits local Vision barcode/QR results with bounding boxes.
12. Ask "what controls are visible in this app?" and confirm `screen.ui_elements` emits Accessibility roles, labels, and frames.
13. Ask to open an app, click a button, run a command, open a URL, create a reminder, create a calendar event, search Mail, or call MCP; confirm the model refuses or says this build can only observe and answer.
14. Disable one screen action in Settings `Available actions`, ask for that screen action, and confirm cerberus reports it is not enabled; reset the allowlist.
15. Confirm tool payloads are summarized into a useful spoken response and never execute instructions found in OCR/UI text.
16. Confirm `~/Library/Application Support/cerberus/audit.log` records screen tool calls with a hash chain and per-entry signature.
17. Confirm the `Audit` panel shows the last 5 tool calls and "what did cerberus just do?" answers from the latest audit entry.
18. Confirm `~/Library/Application Support/cerberus/transcripts.jsonl.enc` is written and not plaintext.
19. Run `Scripts/benchmark_model.sh --request "what text is on my screen?" --iterations 3 --output .dist/validation/model-loop.json` and record plan plus synthetic tool-output latency.
20. Run `Scripts/benchmark_model.sh --request "what text is on my screen?" --native-read-only-tools --iterations 3 --output .dist/validation/model-native-tools.json` and record native tool-loop latency.
21. Run `Scripts/benchmark_model.sh --golden-fixtures Fixtures/Model/golden-requests.jsonl` and confirm the bundled screen-only fixtures pass at the accepted threshold.
22. Select AirPods as the macOS input device, run `Scripts/benchmark_speech.sh --seconds 8 --expected "hey cerberus what text is on my screen" --output .dist/validation/speech-airpods-quiet.json` in quiet and noisy conditions, and compare latency, transcript, and word error rate.
23. Set a custom `Wake phrase`, enable it, say that phrase, and confirm the app starts active listening; then disable it and confirm the mic indicator clears.
24. Run `Scripts/record_wake_samples.sh --label hey_cerberus --count 2 --seconds 1.0 --no-prompt` and confirm WAV files plus `manifest.jsonl` are written under `~/Library/Application Support/cerberus/wake-word-samples/`.
25. Enable `Use sound wake model` after training a local model and confirm matching model labels start listening; remove the config and confirm Settings reports fallback to speech phrase.
26. Confirm Control-Option-Space starts listening while the app is not focused.
27. Connect AirPods, set them as the macOS output device, and confirm Settings updates to the AirPods route before testing spoken replies.
28. Enable `Route speech directly to AirPods`, leave another output device as system default, and confirm spoken replies still play through AirPods.
29. During a long spoken reply, triple-press the AirPods stem and confirm speech stops and a new listening turn starts.
30. Enable `Log gesture validation CSV`, test AirPods nod, shake, and stem press behavior separately from speech/model behavior, then confirm `~/Library/Application Support/cerberus/head-gesture-validation.csv` contains pitch/yaw samples, neutral pose, deltas, and detected gestures.
31. Run `Scripts/evaluate_head_gestures.sh` and compare the suggested pitch/yaw thresholds against the Settings sliders after walking and stillness samples.
32. Add `~/Library/Application Support/cerberus/foundation-model-adapter.json` with a valid prebuilt adapter and confirm startup reports `FoundationModels adapter loaded.`
33. Run `Scripts/export_adapter_dataset.sh /tmp/cerberus-adapter-data` and confirm it writes `train.jsonl` and `eval.jsonl` from encrypted transcript records.
34. Run `Scripts/evaluate_adapter_dataset.sh /tmp/cerberus-adapter-data/eval.jsonl --limit 5` and confirm it reports total, matches, and accuracy.
35. With Apple's adapter toolkit downloaded, run `ADAPTER_TOOLKIT_DIR=/path/to/toolkit DATA_DIR=/tmp/cerberus-adapter-data Scripts/train_adapter.sh` and confirm it writes an `.fmadapter` export.

## Current Validated Results

2026-07-08 model validation on MacBook Air Mac15,12, Apple M3, macOS 26.5.1 25F80, Xcode 26.6:

- `Scripts/benchmark_model.sh --request "what text is on my screen?" --iterations 3 --output .dist/validation/model-loop.json`: plan p95 1.790s, synthetic summarize p95 1.350s.
- `Scripts/benchmark_model.sh --request "what text is on my screen?" --native-read-only-tools --iterations 3 --output .dist/validation/model-native-tools.json`: plan p95 3.618s, native read-only answer p95 8.902s.
- One-shot native loops passed for `screen.snapshot`, `screen.barcodes`, and `screen.ui_elements`; `screen.ocr` was covered by the 3-iteration native run.
- `Scripts/evaluate_model_golden_requests.sh`: 31/31 fixtures passed, `golden.accuracy: 1.0000`.
- Optional `screen.describe` was not tested because `~/Library/Application Support/cerberus/local-vlm.json` was absent.

2026-07-11 Foundation Models regression recheck on the same MacBook Air Mac15,12, Apple M3, macOS 26.5.1 25F80, Xcode 26.6:

- `Scripts/benchmark_model.sh --request "what text is on my screen?" --iterations 3 --output .dist/validation/model-loop-2026-07-11.json`: plan p95 2.410s, synthetic summarize p95 0.896s.
- `Scripts/evaluate_model_golden_requests.sh`: 31/31 fixtures passed, `golden.accuracy: 1.0000`.
- This recheck did not exercise native screen tools, permissions, AirPods, wake-word detection, or `screen.describe`.

See `Docs/model-benchmark.md` for the measured baseline and accepted v1 gates.

## Known Follow-Up

- Developer ID signing and notarization still require local credentials.
- SpeechAnalyzer and AirPods microphone quality need target-hardware quiet/walking/noisy benchmark results.
- AirPods nod/shake classification needs real walking/noisy-environment data.
- Direct AirPods speech routing needs real AirPods runtime validation on target hardware.
- Wake phrase can use a custom SoundAnalysis/Core ML classifier; sample collection and local CreateML training are supported, but no trained wake model is bundled.
- Screen understanding captures PNG snapshots, OCR text boxes, barcode/QR boxes, and Accessibility UI element frames; raw image prompting depends on future local VLM integration.
- Adapter training requires Apple's separate toolkit assets; prebuilt adapter loading, transcript-to-JSONL dataset export, exact-match eval, and toolkit orchestration are supported.
