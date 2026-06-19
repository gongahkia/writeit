# TODO

Generated 2026-06-17 from `IDEA.md`, current repo state, prior implementation history, and official Apple/GitHub references checked during planning.

Legend: `P0` ship blocker, `P1` high-value v1, `P2` hardening, `P3` v2/backlog, `manual` needs human action, `blocked` needs credentials/hardware/assets/external APIs.

## Release gates

- [ ] [P0][release][blocked: Developer ID cert] Install a Developer ID Application certificate in the login keychain.
- [ ] [P0][release][blocked: Developer ID cert] Set `CODESIGN_IDENTITY` to the installed Developer ID Application identity.
- [ ] [P0][release] Build `.dist/cerberus.app` with `CODESIGN_IDENTITY` using `Scripts/build_app.sh`.
- [ ] [P0][release] Run `Scripts/release_check.sh dev-id` against the Developer ID signed app.
- [ ] [P0][release][blocked: Apple notary credentials] Create or select a `notarytool` keychain profile for cerberus.
- [ ] [P0][release][blocked: Apple notary credentials] Set `NOTARY_PROFILE` to the usable notary profile.
- [ ] [P0][release] Run `Scripts/notarize_app.sh` and staple the notarization ticket to `.dist/cerberus.app`.
- [ ] [P0][release] Run `Scripts/release_check.sh notary` after stapling.
- [ ] [P0][release] Run `Scripts/package_release.sh` with Developer ID signing and notarization enabled.
- [ ] [P0][release] Verify `.dist/release/cerberus.zip` and `.dist/release/cerberus.zip.sha256` exist and match the final signed app.
- [ ] [P0][release] Run `spctl --assess --type execute --verbose=2 .dist/cerberus.app` on the final notarized bundle.
- [ ] [P0][release] Run `codesign --verify --deep --strict --verbose=2 .dist/cerberus.app` on the final notarized bundle.
- [ ] [P0][release] Run a clean-account launch smoke test from the signed `.app`, not from `swift run`.
- [ ] [P0][release] Confirm `ShellExecService.xpc` is embedded at `Contents/XPCServices/ShellExecService.xpc` in the final app bundle.
- [ ] [P0][release] Confirm `ShellExecService.xpc` is signed before the parent app bundle in release packaging.
- [ ] [P0][release] Confirm the final `.app` launches after download/quarantine simulation.
- [ ] [P0][release] Confirm the app runs on the lowest supported macOS 26 build targeted by `Package.swift`.

## Open-source readiness

- [ ] [P0][oss][manual] Choose a repository license before publishing.
- [ ] [P0][oss][manual] Add root `LICENSE` or `COPYING` with the chosen license text.
- [ ] [P0][oss] Add a README license section matching the chosen root license.
- [ ] [P0][oss] Run `Scripts/open_source_check.sh license` after adding the license.
- [ ] [P0][oss][manual] Review GitHub Actions logs and artifacts for sensitive paths or data before making the repository public.
- [ ] [P0][oss][manual] Review GitHub repository settings before making the repository public.
- [ ] [P0][oss][manual] Enable or verify Dependabot alerts for the public repository.
- [ ] [P0][oss][manual] Enable or verify secret scanning for the public repository.
- [ ] [P0][oss][manual] Enable or verify push protection for the public repository.
- [ ] [P0][oss][manual] Enable or verify code scanning if the repo will accept outside contributions.
- [ ] [P0][oss][manual] Make the GitHub repository public only after explicit approval.
- [ ] [P0][oss] Run `Scripts/release_check.sh oss` after the repository is public.
- [ ] [P2][oss] Add repository topics after public release so the project is discoverable.

## Hardware validation

- [ ] [P0][hardware][blocked: macOS 26 target Mac] Validate app launch, menu bar behavior, and permissions on real macOS 26 hardware.
- [ ] [P0][hardware][blocked: Apple Intelligence capable Mac] Validate Foundation Models availability on the target Mac with Apple Intelligence enabled.
- [ ] [P0][hardware][blocked: AirPods] Validate AirPods input selection before speech benchmarks.
- [ ] [P0][hardware][blocked: AirPods] Validate AirPods output selection before spoken response tests.
- [ ] [P0][hardware][blocked: AirPods] Validate direct AirPods speech routing while system output is not AirPods.
- [ ] [P0][hardware][blocked: AirPods] Validate direct AirPods speech routing while AirPods reconnect mid-session.
- [ ] [P0][hardware][blocked: AirPods] Validate direct AirPods speech routing after the default output device changes.
- [ ] [P0][hardware][blocked: AirPods] Validate spoken replies remain audible after sleep/wake and AirPods reconnect.
- [ ] [P0][hardware][blocked: AirPods] Validate long spoken response interruption via stem triple-press.
- [ ] [P0][hardware][blocked: AirPods] Validate app behavior when AirPods disconnect during listening.
- [ ] [P0][hardware][blocked: AirPods] Validate app behavior when AirPods disconnect during speaking.
- [ ] [P0][hardware][blocked: AirPods] Validate app behavior when AirPods disconnect during confirmation voice capture.
- [ ] [P0][hardware][blocked: clean macOS account] Validate first-run setup from zero permissions.
- [ ] [P0][hardware][blocked: clean macOS account] Validate denied microphone permission produces a usable recovery path.
- [ ] [P0][hardware][blocked: clean macOS account] Validate denied Speech Recognition permission produces a usable recovery path.
- [ ] [P0][hardware][blocked: clean macOS account] Validate denied Accessibility permission produces a usable recovery path.
- [ ] [P0][hardware][blocked: clean macOS account] Validate denied Input Monitoring permission produces a usable recovery path.
- [ ] [P0][hardware][blocked: clean macOS account] Validate denied Screen Recording permission fails screen tools closed.
- [ ] [P0][hardware][blocked: clean macOS account] Validate denied Calendar access fails calendar read/create tools closed.
- [ ] [P0][hardware][blocked: clean macOS account] Validate denied Reminders access fails reminders read/create/complete tools closed.
- [ ] [P1][hardware] Store validation JSON/CSV artifacts under `.dist/validation/` during manual QA.
- [ ] [P1][hardware] Add a dated validation summary doc after target-hardware runs.

## AirPods trigger quality

- [ ] [P0][airpods][blocked: AirPods] Record head-gesture validation CSV while sitting still for at least 5 minutes.
- [ ] [P0][airpods][blocked: AirPods] Record head-gesture validation CSV while typing for at least 5 minutes.
- [ ] [P0][airpods][blocked: AirPods] Record head-gesture validation CSV while walking indoors for at least 10 minutes.
- [ ] [P0][airpods][blocked: AirPods] Record head-gesture validation CSV while walking outdoors for at least 10 minutes.
- [ ] [P0][airpods][blocked: AirPods] Record head-gesture validation CSV while nodding intentionally at least 50 times.
- [ ] [P0][airpods][blocked: AirPods] Record head-gesture validation CSV while shaking intentionally at least 50 times.
- [ ] [P0][airpods][blocked: AirPods] Run `Scripts/evaluate_head_gestures.sh` on each validation CSV.
- [ ] [P0][airpods][blocked: AirPods] Tune default nod threshold from real false-positive and true-positive data.
- [ ] [P0][airpods][blocked: AirPods] Tune default shake threshold from real false-positive and true-positive data.
- [ ] [P0][airpods][blocked: AirPods] Validate neutral-pose calibration before and after walking.
- [ ] [P0][airpods][blocked: AirPods] Validate nod while `awaitingConfirm` approves only the pending confirmation.
- [ ] [P0][airpods][blocked: AirPods] Validate shake while `awaitingConfirm` denies only the pending confirmation.
- [ ] [P0][airpods][blocked: AirPods] Validate shake while idle does not cancel unrelated state.
- [ ] [P0][airpods][blocked: AirPods] Validate stem single-press cancels listening.
- [ ] [P0][airpods][blocked: AirPods] Validate stem single-press denies pending confirmation.
- [ ] [P0][airpods][blocked: AirPods] Validate stem triple-press starts listening from idle.
- [ ] [P0][airpods][blocked: AirPods] Validate stem triple-press interrupts speaking and starts a new turn.
- [ ] [P1][airpods] Add hardware validation thresholds to docs after real-data tuning.

## Speech and wake-word quality

- [ ] [P0][speech][blocked: AirPods] Run `Scripts/benchmark_speech.sh --seconds 8 --expected "hey cerberus open calendar" --output .dist/validation/speech-airpods-quiet.json` in a quiet room.
- [ ] [P0][speech][blocked: AirPods] Run `Scripts/benchmark_speech.sh --seconds 8 --expected "hey cerberus open calendar" --output .dist/validation/speech-airpods-walking.json` while walking.
- [ ] [P0][speech][blocked: AirPods] Run `Scripts/benchmark_speech.sh --seconds 8 --expected "hey cerberus open calendar" --output .dist/validation/speech-airpods-noisy.json` in a noisy room.
- [ ] [P0][speech][blocked: AirPods] Compare first update latency across quiet, walking, and noisy AirPods benchmarks.
- [ ] [P0][speech][blocked: AirPods] Compare finalization duration across quiet, walking, and noisy AirPods benchmarks.
- [ ] [P0][speech][blocked: AirPods] Compare word error rate across quiet, walking, and noisy AirPods benchmarks.
- [ ] [P0][speech][blocked: AirPods] Define acceptable v1 speech latency thresholds from actual benchmark output.
- [ ] [P0][speech][blocked: AirPods] Define acceptable v1 speech word-error thresholds from actual benchmark output.
- [ ] [P0][speech][blocked: AirPods] Validate silence auto-run after 1.5 seconds with short commands.
- [ ] [P0][speech][blocked: AirPods] Validate silence auto-run does not cut off longer natural requests.
- [ ] [P0][speech][blocked: AirPods] Validate manual `Run` during listening does not duplicate transcription or execution.
- [ ] [P0][speech][blocked: AirPods] Validate cancel during listening stops the transcriber and clears the microphone indicator.
- [ ] [P0][speech][blocked: AirPods] Validate confirmation voice capture hears "yes" and approves.
- [ ] [P0][speech][blocked: AirPods] Validate confirmation voice capture hears "no" and denies.
- [ ] [P0][speech][blocked: AirPods] Validate confirmation voice timeout returns to a safe state.
- [ ] [P1][wake][blocked: AirPods] Collect at least 40 `hey_cerberus` wake samples through AirPods mic in quiet conditions.
- [ ] [P1][wake][blocked: AirPods] Collect at least 40 `hey_cerberus` wake samples through AirPods mic while walking.
- [ ] [P1][wake][blocked: AirPods] Collect at least 40 background samples through AirPods mic in quiet conditions.
- [ ] [P1][wake][blocked: AirPods] Collect at least 40 background samples through AirPods mic while walking.
- [ ] [P1][wake][blocked: AirPods] Collect at least 40 negative samples for music, keyboard, conversation, and noisy room classes.
- [ ] [P1][wake] Run `Scripts/train_wake_word_model.sh --target-label hey_cerberus --write-config` after collecting a balanced local dataset.
- [ ] [P1][wake] Validate generated `CerberusWakeWord.mlmodel` loads at app startup.
- [ ] [P1][wake] Validate `.mlmodel` compilation to `.mlmodelc` at runtime.
- [ ] [P1][wake] Validate false-positive rate for the trained wake model in quiet, walking, and noisy conditions.
- [ ] [P1][wake] Validate false-negative rate for the trained wake model in quiet, walking, and noisy conditions.
- [ ] [P2][wake][Inference] Add wake-model confidence threshold guidance after collecting real validation metrics.

## Foundation Models and SDK work

- [ ] [P0][model][blocked: macOS 26 SDK] Run `Scripts/benchmark_model.sh --request "what text is on my screen?" --iterations 3 --output .dist/validation/model-loop.json` on target hardware.
- [ ] [P0][model][blocked: Apple Intelligence capable Mac] Validate Foundation Models planning returns direct answers and typed tool plans on target hardware.
- [ ] [P0][model][blocked: Apple Intelligence capable Mac] Validate native read-only tool mode with `Scripts/benchmark_model.sh --native-read-only-tools`.
- [ ] [P0][model][blocked: Apple Intelligence capable Mac] Validate tool-output summarization latency with real screen, calendar, mail, file, web, and music tool payloads.
- [ ] [P0][model][blocked: Apple Intelligence capable Mac] Define acceptable v1 planning latency from measured hardware output.
- [ ] [P0][model][blocked: Apple Intelligence capable Mac] Define acceptable v1 tool-loop latency from measured hardware output.
- [ ] [P1][model] Add a model benchmark regression baseline to docs after hardware measurements.

## Adapter training and data

- [ ] [P0][adapter][blocked: real transcripts] Generate enough real transcript history for adapter dataset export.
- [ ] [P0][adapter] Run `Scripts/export_adapter_dataset.sh` after transcript history exists.
- [ ] [P0][adapter] Inspect `train.jsonl` for private data before using it for training.
- [ ] [P0][adapter] Inspect `eval.jsonl` for private data before using it for training.
- [ ] [P0][adapter] Curate transcript-derived prompt/response rows before model training.
- [ ] [P0][adapter] Remove failed, unsafe, or low-quality assistant responses from the training split.
- [ ] [P0][adapter] Remove failed, unsafe, or low-quality assistant responses from the eval split.
- [ ] [P0][adapter] Run `Scripts/evaluate_adapter_dataset.sh` on the eval split before training.
- [ ] [P0][adapter][blocked: Apple toolkit assets] Download the matching Apple Foundation Models adapter training toolkit.
- [ ] [P0][adapter][blocked: Apple toolkit assets] Set `ADAPTER_TOOLKIT_DIR` to the local toolkit path.
- [ ] [P0][adapter][blocked: Python env] Create a Python environment compatible with the adapter toolkit.
- [ ] [P0][adapter][blocked: Apple toolkit assets] Run `Scripts/train_adapter.sh` with curated train/eval data.
- [ ] [P0][adapter][blocked: Apple toolkit assets] Export an `.fmadapter` artifact after training.
- [ ] [P0][adapter][blocked: Apple toolkit assets] Configure `foundation-model-adapter.json` to load the trained adapter.
- [ ] [P0][adapter][blocked: Apple toolkit assets] Validate app startup reports the adapter loaded.
- [ ] [P0][adapter][blocked: Apple toolkit assets] Run adapter eval with `--adapter-config` after loading the adapter.
- [ ] [P0][adapter][blocked: Apple toolkit assets] Compare base-model and adapter eval outputs.
- [ ] [P0][adapter][blocked: Apple toolkit assets] Document adapter compatibility with the exact system model version used for training.
- [ ] [P0][adapter][blocked: Apple toolkit assets] Re-train adapters for every incompatible system-model version.

## Screen and multimodal work


## UX, onboarding, and settings polish

- [ ] [P0][ux] Validate every state transition has the intended earcon on target hardware.

## Docs, demo, and release assets

- [ ] [P0][docs] Update `Docs/macos-validation.md` with actual hardware validation results.
- [ ] [P0][docs] Update `Docs/distribution.md` after the first notarized release succeeds.
- [ ] [P0][docs] Update `Docs/open-source.md` after the license and repo visibility decisions are complete.
- [ ] [P0][docs] Update `README.md` with real validated requirements after target-hardware QA.

## Tests and CI

- [ ] [P0][tests] Keep `swift test` passing before every release.
- [ ] [P1][ci][blocked: signing secrets] Add optional release packaging workflow only after secret storage policy is decided.

## V2 and product expansion

- [ ] [P2][product][Inference] Add deeper Finder integration if file tasks dominate real usage.
- [ ] [P2][product][Inference] Add Shortcuts integration if users want to call existing automations.
- [ ] [P2][product][Inference] Add app-specific tool packs for Xcode, Terminal, Safari, Chrome, Calendar, Mail, and Music.
- [ ] [P2][product][Inference] Add local vector memory only after encrypted memory UX and deletion controls exist.
- [ ] [P2][product][Inference] Add background task queue only after cancellation and audit semantics are designed.
- [ ] [P2][product][Inference] Add plugin-like local tool registration only after security model review.
- [ ] [P3][product][Speculation] Explore iOS companion only as a separate project.
- [ ] [P3][product][Speculation] Explore non-AirPods trigger surfaces only if AirPods validation is weak.
- [ ] [P3][product][Speculation] Explore cloud model fallback only if local Foundation Models quality is insufficient and privacy scope changes.

## Reference re-check tasks
