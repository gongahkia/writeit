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
- [ ] [P0][airpods][blocked: AirPods] Validate threshold sliders persist across app relaunch.
- [ ] [P0][airpods][blocked: AirPods] Validate neutral-pose calibration before and after walking.
- [ ] [P0][airpods][blocked: AirPods] Validate nod while `awaitingConfirm` approves only the pending confirmation.
- [ ] [P0][airpods][blocked: AirPods] Validate shake while `awaitingConfirm` denies only the pending confirmation.
- [ ] [P0][airpods][blocked: AirPods] Validate shake while idle does not cancel unrelated state.
- [ ] [P0][airpods][blocked: AirPods] Validate stem single-press cancels listening.
- [ ] [P0][airpods][blocked: AirPods] Validate stem single-press denies pending confirmation.
- [ ] [P0][airpods][blocked: AirPods] Validate stem triple-press starts listening from idle.
- [ ] [P0][airpods][blocked: AirPods] Validate stem triple-press interrupts speaking and starts a new turn.
- [ ] [P1][airpods] Add hardware validation thresholds to docs after real-data tuning.
- [ ] [P2][airpods][Inference] Add optional per-user threshold profile export/import if validation shows thresholds vary materially.
- [ ] [P2][airpods][Inference] Add a cooldown tuning control if validation shows accidental repeated triggers.

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
- [ ] [P1][wake] Validate `wake-word-sound-classifier.json` fallback to SpeechAnalyzer phrase mode after config removal.
- [ ] [P1][wake] Validate false-positive rate for the trained wake model in quiet, walking, and noisy conditions.
- [ ] [P1][wake] Validate false-negative rate for the trained wake model in quiet, walking, and noisy conditions.
- [ ] [P2][wake][Inference] Add wake-model confidence threshold guidance after collecting real validation metrics.
- [ ] [P2][wake][Inference] Add optional sample-quality report before training if poor recordings cause classifier failures.

## Foundation Models and SDK work

- [ ] [P0][model][blocked: macOS 26 SDK] Run `Scripts/benchmark_model.sh --request "what text is on my screen?" --iterations 3 --output .dist/validation/model-loop.json` on target hardware.
- [ ] [P0][model][blocked: Apple Intelligence capable Mac] Validate Foundation Models planning returns direct answers and typed tool plans on target hardware.
- [ ] [P0][model][blocked: Apple Intelligence capable Mac] Validate native read-only tool mode with `Scripts/benchmark_model.sh --native-read-only-tools`.
- [ ] [P0][model][blocked: Apple Intelligence capable Mac] Validate tool-output summarization latency with real screen, calendar, mail, file, web, and music tool payloads.
- [ ] [P0][model][blocked: Apple Intelligence capable Mac] Define acceptable v1 planning latency from measured hardware output.
- [ ] [P0][model][blocked: Apple Intelligence capable Mac] Define acceptable v1 tool-loop latency from measured hardware output.
- [ ] [P0][model] Re-check installed FoundationModels swiftinterface before each SDK bump.
- [ ] [P0][model] Re-check Apple Foundation Models docs before each SDK bump.
- [ ] [P0][model][Unverified] Re-evaluate image-prompt and vision attachment support against the current macOS 26 SDK.
- [ ] [P0][model][Unverified] Re-evaluate Apple-provided OCRTool and BarcodeReaderTool availability against the current macOS 26 SDK.
- [ ] [P1][model][Inference] Replace or augment OCR-only screen reasoning if public image prompt APIs are available in the installed SDK.
- [ ] [P1][model][Inference] Add model-availability diagnostics if target machines lack required Apple Intelligence state.
- [ ] [P1][model] Add a model benchmark regression baseline to docs after hardware measurements.
- [ ] [P2][model][Unverified] Re-evaluate Private Cloud Compute model APIs for optional non-local mode only if product scope changes.
- [ ] [P2][model][Unverified] Re-evaluate dynamic model profile APIs for future quality/latency tradeoffs.
- [ ] [P2][model][Inference] Add a local-only hard lock setting if future SDKs expose non-local model choices.
- [ ] [P2][model][Inference] Add prompt/version metadata to transcript records for adapter and regression analysis.
- [ ] [P2][model][Inference] Add golden request fixtures for common tasks and track model plan drift across SDK updates.

## Tool safety and confirmation QA

- [ ] [P0][safety] Validate every mutating built-in tool enters `awaitingConfirm` before execution.
- [ ] [P0][safety] Validate every read-only built-in tool can run without confirmation when enabled.
- [ ] [P0][safety] Validate disabled ambient tools are omitted from the planner prompt.
- [ ] [P0][safety] Validate disabled ambient tools cannot execute through `ToolRegistry`.
- [ ] [P0][safety] Validate `shell.run` is disabled by default in a fresh app launch.
- [ ] [P0][safety] Validate enabling `shell.run` requires explicit user action in Settings.
- [ ] [P0][safety] Validate `shell.run` requires confirmation even for read-only allowlisted commands.
- [ ] [P0][safety] Validate `shell.run` uses `ShellExecService.xpc` in the packaged `.app`.
- [ ] [P0][safety] Validate `shell.run` fails closed if `ShellExecService.xpc` is missing.
- [ ] [P0][safety] Validate `shell.run` rejects home-prefix sibling working directories.
- [ ] [P0][safety] Validate `shell.run` rejects symlink escapes from the user home.
- [ ] [P0][safety] Validate `shell.run` rejects denied shell fragments in arguments.
- [ ] [P0][safety] Validate `shell.run` rejects mutating git, brew, npm, and swift subcommands.
- [ ] [P0][safety] Validate `web.search` rejects non-allowlisted domains at runtime.
- [ ] [P0][safety] Validate `files.search` fails closed when no approved folders exist.
- [ ] [P0][safety] Validate explicit `files.search` scope must stay inside an approved folder.
- [ ] [P0][safety] Validate `mail.search` never changes read status.
- [ ] [P0][safety] Validate `music.control` requires confirmation for play, pause, stop, next, previous, and play/pause.
- [ ] [P0][safety] Validate `calendar.create` requires confirmation and rejects invalid duration/end times.
- [ ] [P0][safety] Validate `reminders.create` requires confirmation and rejects empty titles.
- [ ] [P0][safety] Validate `reminders.complete` requires confirmation and handles ambiguous matches safely.
- [ ] [P0][safety] Validate screen tools fail closed without Screen Recording permission.
- [ ] [P0][safety] Validate prompt-boundary escaping for nested tool payloads from every tool family.
- [ ] [P0][safety] Validate audit entries are hash-chained and HMAC-signed after real app tool calls.
- [ ] [P0][safety] Validate audit signature verification detects tampered log entries.
- [ ] [P0][safety] Validate transcript file does not contain plaintext request or response text.
- [ ] [P0][safety] Validate memory file does not contain plaintext memory text.
- [ ] [P0][safety] Validate Keychain deletion forces new encryption/signing keys and produces a clear recovery state.
- [ ] [P1][safety] Add a user-visible export/delete control for transcripts.
- [ ] [P1][safety] Add a user-visible export/delete control for memories.
- [ ] [P1][safety] Add a user-visible clear/reset control for audit history if product policy allows deletion.
- [ ] [P1][safety] Add tests for tool-output summarization fallback when Foundation Models summarization fails.
- [ ] [P1][safety] Add tests for `answerLastToolAction()` using a seeded audit log.
- [ ] [P2][safety][Inference] Add optional "paranoid mode" where all tools, including read-only tools, require confirmation.
- [ ] [P2][safety][Inference] Add per-tool confirmation overrides if real use shows current defaults are too strict or too loose.

## MCP validation

- [ ] [P0][mcp] Validate MCP tools stay disabled by default on fresh launch.
- [ ] [P0][mcp] Validate enabling `MCP tool` starts Streamable HTTP GET listeners only for configured HTTP servers.
- [ ] [P0][mcp][blocked: test MCP stdio server] Validate stdio `tools/list` and `tools/call`.
- [ ] [P0][mcp][blocked: test MCP stdio server] Validate stdio `resources/list` and `resources/read`.
- [ ] [P0][mcp][blocked: test MCP stdio server] Validate stdio `prompts/list` and `prompts/get`.
- [ ] [P0][mcp][blocked: test MCP stdio server] Validate stdio `sampling/createMessage` prompt review.
- [ ] [P0][mcp][blocked: test MCP stdio server] Validate stdio `sampling/createMessage` response review.
- [ ] [P0][mcp][blocked: test MCP stdio server] Validate stdio `elicitation/create` accept flow.
- [ ] [P0][mcp][blocked: test MCP stdio server] Validate stdio `elicitation/create` decline flow.
- [ ] [P0][mcp][blocked: test MCP stdio server] Validate stdio `elicitation/create` cancel flow.
- [ ] [P0][mcp][blocked: test MCP HTTP server] Validate Streamable HTTP `tools/list` and `tools/call`.
- [ ] [P0][mcp][blocked: test MCP HTTP server] Validate Streamable HTTP `resources/list` and `resources/read`.
- [ ] [P0][mcp][blocked: test MCP HTTP server] Validate Streamable HTTP `prompts/list` and `prompts/get`.
- [ ] [P0][mcp][blocked: test MCP HTTP server] Validate Streamable HTTP POST responses with SSE server requests.
- [ ] [P0][mcp][blocked: test MCP HTTP server] Validate Streamable HTTP GET listener reconnection with `Last-Event-ID`.
- [ ] [P0][mcp][blocked: OAuth MCP server] Validate OAuth protected-resource discovery.
- [ ] [P0][mcp][blocked: OAuth MCP server] Validate OAuth dynamic client registration when supported.
- [ ] [P0][mcp][blocked: OAuth MCP server] Validate OAuth static client ID path when dynamic registration is unavailable.
- [ ] [P0][mcp][blocked: OAuth MCP server] Validate OAuth PKCE authorization URL opens in the browser.
- [ ] [P0][mcp][blocked: OAuth MCP server] Validate OAuth localhost callback capture.
- [ ] [P0][mcp][blocked: OAuth MCP server] Validate OAuth token exchange and Keychain storage.
- [ ] [P0][mcp][blocked: OAuth MCP server] Validate OAuth refresh-token rotation.
- [ ] [P0][mcp][blocked: OAuth MCP server] Validate stored bearer token attachment to later HTTP calls.
- [ ] [P0][mcp] Validate explicit config `headers.Authorization` precedence over stored OAuth token.
- [ ] [P0][mcp] Validate `mcp.call` is confirmation-gated for all configured servers.
- [ ] [P0][mcp] Validate `nativeReadOnlyTools` rejects nested schemas.
- [ ] [P0][mcp] Validate `nativeReadOnlyTools` exposes only trusted read-only tool names.
- [ ] [P0][mcp] Validate mutating MCP tools are never exposed through native FoundationModels read-only tool sessions.
- [ ] [P2][mcp][Inference] Add per-server UI health indicators if multiple MCP servers are common.
- [ ] [P2][mcp][Inference] Add per-server enable/disable controls if multiple MCP servers are common.

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
- [ ] [P1][adapter] Add non-exact-match eval metrics for tool-selection quality.
- [ ] [P1][adapter] Add non-exact-match eval metrics for spoken-response quality.
- [ ] [P2][adapter][Inference] Add adapter A/B toggle in Settings if adapter quality is mixed.
- [ ] [P2][adapter][Inference] Add automatic adapter disable on repeated model failures.

## Screen and multimodal work

- [ ] [P0][screen] Validate `screen.snapshot` writes PNG files under `~/Library/Caches/cerberus/screen-snapshots/`.
- [ ] [P0][screen] Validate `screen.snapshot` fails closed when Screen Recording is denied.
- [ ] [P0][screen] Validate `screen.ocr` returns local Vision text with normalized bounding boxes.
- [ ] [P0][screen] Validate `screen.ocr` returns pixel bounding boxes.
- [ ] [P0][screen] Validate `screen.ocr` fails closed when Screen Recording is denied.
- [ ] [P1][screen] Add OCR confidence and language reporting if Vision exposes reliable values in the SDK.
- [ ] [P1][screen][Unverified] Re-check Apple Foundation Models image attachment support before keeping OCR-only screen reasoning.
- [ ] [P1][screen][Unverified] Re-check Apple Vision OCRTool availability before maintaining a custom OCR-only prompt path.
- [ ] [P1][screen][Inference] Add image-prompt based screen answering if public APIs exist in the installed SDK.
- [ ] [P2][screen][Inference] Add region selection for screen OCR if whole-screen OCR is too noisy.
- [ ] [P2][screen][Inference] Add active-window-only screen capture if full-display capture is too broad for privacy.
- [ ] [P2][screen][Inference] Add redaction for notification banners and sensitive fields before model ingress.
- [ ] [P3][screen][Inference] Add barcode/QR recognition if real screen tasks need it.
- [ ] [P3][screen][Inference] Add UI-element detection beyond OCR if app-control tasks need coordinates.

## UX, onboarding, and settings polish

- [ ] [P0][ux] Validate setup banner opens the Access panel when permissions are missing.
- [ ] [P0][ux] Validate setup skip persists across app relaunch.
- [ ] [P0][ux] Validate setup reset clears the skip flag and refreshes permissions.
- [ ] [P0][ux] Validate microphone-active menu bar tint is red while listening.
- [ ] [P0][ux] Validate microphone-active menu bar tint is red during wake phrase monitoring.
- [ ] [P0][ux] Validate microphone-active menu bar tint is red during confirmation voice capture.
- [ ] [P0][ux] Validate menu bar icon returns to non-red after microphone stops.
- [ ] [P0][ux] Validate every state transition has the intended earcon on target hardware.
- [ ] [P0][ux] Validate `Recent transitions` remains useful after repeated long sessions.
- [ ] [P0][ux] Validate transcript history refresh after real app sessions.
- [ ] [P0][ux] Validate audit panel refresh after real tool calls.
- [ ] [P0][ux] Validate "What did cerberus just do?" speaks the latest audit action.
- [ ] [P0][ux] Validate settings toggles persist where they should persist.
- [ ] [P0][ux] Validate settings toggles reset where they should not persist.
- [ ] [P0][ux] Validate File Search folder add/remove flows.
- [ ] [P0][ux] Validate tool allowlist disclosure layout with all current tools enabled.
- [ ] [P0][ux] Validate tool allowlist layout with several disabled tools.
- [ ] [P0][ux] Validate MCP review controls with long prompts and responses.
- [ ] [P0][ux] Validate MCP elicitation controls with boolean, enum, number, integer, and string fields.
- [ ] [P1][ux] Replace any user-facing text that is too implementation-heavy for a voice-first utility.
- [ ] [P1][ux] Add concise recovery copy for each denied permission.
- [ ] [P1][ux] Add app-data location display for audit, transcripts, memory, wake samples, adapter config, MCP config, and screen snapshots.
- [ ] [P1][ux] Add "Reveal in Finder" controls for validation artifacts and app data directories.
- [ ] [P1][ux] Add a first-run checklist summary once setup completes.
- [ ] [P1][ux] Add keyboard accessibility review for the panel controls.
- [ ] [P1][ux] Add VoiceOver labels for icon-only buttons.
- [ ] [P1][ux] Add dynamic type/layout review for long paths and long tool names.
- [ ] [P1][ux] Add dark/light appearance review screenshots.
- [ ] [P2][ux][Inference] Add menu command shortcuts for Listen, Cancel, Refresh Permissions, and Open Settings.
- [ ] [P2][ux][Inference] Add configurable hotkey if Control-Option-Space conflicts in real use.
- [ ] [P2][ux][Inference] Add onboarding progress persistence per permission if setup flow becomes longer.

## Docs, demo, and release assets

- [ ] [P0][docs] Update `Docs/macos-validation.md` with actual hardware validation results.
- [ ] [P0][docs] Update `Docs/implementation-notes.md` after any SDK-driven Foundation Models changes.
- [ ] [P0][docs] Update `Docs/distribution.md` after the first notarized release succeeds.
- [ ] [P0][docs] Update `Docs/open-source.md` after the license and repo visibility decisions are complete.
- [ ] [P0][docs] Update `README.md` with real validated requirements after target-hardware QA.
- [ ] [P1][docs] Add screenshots of the menu bar panel after UI stabilizes.

## Tests and CI

- [ ] [P0][tests] Keep `swift test` passing before every release.
- [ ] [P1][tests] Add tests for settings persistence keys.
- [ ] [P1][tests] Add tests for wake-word monitor fallback state strings.
- [ ] [P1][tests] Add tests for direct AirPods route selection with fake CoreAudio devices.
- [ ] [P1][tests] Add tests for silence auto-run scheduling using injectable clocks.
- [ ] [P1][tests] Add tests for confirmation voice timeout using injectable clocks.
- [ ] [P1][tests] Add tests for app model transitions using fake transcriber, speaker, assistant, and tools.
- [ ] [P1][tests] Add tests for packaged app bundle file layout.
- [ ] [P1][tests] Add tests for release scripts in check-only or dry-run mode where possible.
- [ ] [P1][tests] Add tests for adapter dataset privacy/redaction once redaction exists.
- [ ] [P1][tests] Add tests for MCP config validation edge cases.
- [ ] [P1][tests] Add tests for MCP OAuth config precedence.
- [ ] [P1][tests] Add tests for file-search approved-folder persistence failures.
- [ ] [P1][tests] Add tests for Keychain read/write/delete failures with injectable store fakes.
- [ ] [P1][ci] Add GitHub Actions workflow for `swift test` on macOS 26 when hosted runner support exists.
- [ ] [P1][ci][blocked: signing secrets] Add optional release packaging workflow only after secret storage policy is decided.
- [ ] [P1][ci] Add CI artifact upload for test logs and validation reports.
- [ ] [P2][ci] Add nightly build against latest Xcode beta if the project tracks macOS 26 SDK changes.
- [ ] [P2][ci] Add static grep check for forbidden hardcoded credentials.
- [ ] [P2][ci] Add script linting for `Scripts/*.sh`.

## V2 and product expansion

- [ ] [P2][product][Inference] Add configurable tool profiles for ambient, trusted desk, and explicit operator modes.
- [ ] [P2][product][Inference] Add per-app context policies for the active macOS application.
- [ ] [P2][product][Inference] Add deeper Finder integration if file tasks dominate real usage.
- [ ] [P2][product][Inference] Add Mail body search only behind explicit opt-in and privacy copy.
- [ ] [P2][product][Inference] Add Calendar edit/delete tools only after confirmation UX is proven with create.
- [ ] [P2][product][Inference] Add Reminder edit/delete tools only after confirmation UX is proven with create/complete.
- [ ] [P2][product][Inference] Add Notes read/search tool if local notes queries are a common workflow.
- [ ] [P2][product][Inference] Add Contacts read tool if scheduling workflows need attendee lookup.
- [ ] [P2][product][Inference] Add Shortcuts integration if users want to call existing automations.
- [ ] [P2][product][Inference] Add app-specific tool packs for Xcode, Terminal, Safari, Chrome, Calendar, Mail, and Music.
- [ ] [P2][product][Inference] Add local vector memory only after encrypted memory UX and deletion controls exist.
- [ ] [P2][product][Inference] Add memory scopes for personal preferences, project facts, and temporary session facts.
- [ ] [P2][product][Inference] Add "forget this" voice command for memory records.
- [ ] [P2][product][Inference] Add project/workspace detection for coding tasks.
- [ ] [P2][product][Inference] Add terminal command proposal mode that never executes commands.
- [ ] [P2][product][Inference] Add spoken diff summary for shell/git read-only outputs.
- [ ] [P2][product][Inference] Add local notification integration for long-running tasks.
- [ ] [P2][product][Inference] Add background task queue only after cancellation and audit semantics are designed.
- [ ] [P2][product][Inference] Add multi-turn follow-up context after transcript privacy controls are complete.
- [ ] [P2][product][Inference] Add per-session "do not remember" toggle.
- [ ] [P2][product][Inference] Add latency/quality telemetry stored locally only.
- [ ] [P2][product][Inference] Add diagnostics export bundle with redaction.
- [ ] [P2][product][Inference] Add plugin-like local tool registration only after security model review.
- [ ] [P3][product][Speculation] Explore iOS companion only as a separate project.
- [ ] [P3][product][Speculation] Explore non-AirPods trigger surfaces only if AirPods validation is weak.
- [ ] [P3][product][Speculation] Explore cloud model fallback only if local Foundation Models quality is insufficient and privacy scope changes.

## Reference re-check tasks

- [ ] [P0][reference] Re-check Apple Foundation Models docs before implementing any model API upgrade: https://developer.apple.com/documentation/foundationmodels/
- [ ] [P0][reference] Re-check Apple Foundation Models updates before implementing image/vision work: https://developer.apple.com/documentation/updates/foundationmodels
- [ ] [P0][reference] Re-check Apple `SystemLanguageModel.Adapter` docs before adapter shipping: https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/adapter
- [ ] [P0][reference] Re-check Apple SpeechAnalyzer docs before speech pipeline changes: https://developer.apple.com/documentation/speech/speechanalyzer
- [ ] [P0][reference] Re-check Apple SpeechTranscriber docs before transcription behavior changes: https://developer.apple.com/documentation/speech/speechtranscriber
- [ ] [P0][reference] Re-check GitHub license docs before public release: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository
- [ ] [P0][reference] Re-check GitHub repository visibility docs before public release: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility
- [ ] [P0][reference] Re-check GitHub security and analysis docs before public release: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-security-and-analysis-settings-for-your-repository
