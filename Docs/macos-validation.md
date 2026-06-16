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
2. Request Microphone, Speech Recognition, and Screen Recording permissions.
3. Press `Listen`, speak a short request, then wait 1.5 seconds or press `Run`.
4. Confirm SpeechAnalyzer transcribes into the request field and silence moves to reasoning.
5. Enable `Wake phrase`, say "hey cerberus", and confirm the app starts active listening; then disable it and confirm the mic indicator clears.
6. Confirm Control-Option-Space starts listening while the app is not focused.
7. Connect AirPods, set them as the macOS output device, and confirm Settings shows the AirPods route before testing spoken replies.
8. Confirm Foundation Models returns either a direct spoken response or a typed tool plan.
9. Trigger a read-only tool request, such as "what is playing in Music?", "search my files for README", "search my mail for Apple", or "what text is on my screen?".
10. Confirm tool payloads are summarized into a useful spoken response.
11. Add `~/Library/Application Support/cerberus/foundation-model-adapter.json` with a valid prebuilt adapter and confirm startup reports `FoundationModels adapter loaded.`.
12. Confirm `~/Library/Application Support/cerberus/audit.log` records tool calls with a hash chain and per-entry signature.
13. Confirm the `Audit` panel shows the last 5 tool calls and "what did cerberus just do?" answers from the latest audit entry.
14. Confirm `~/Library/Application Support/cerberus/transcripts.jsonl.enc` is written and not plaintext.
15. Ask cerberus to remember a preference and confirm `~/Library/Application Support/cerberus/memory.jsonl.enc` is written and not plaintext.
16. Confirm screen OCR emits only local Vision text results and fails closed when Screen Recording is denied.
17. Trigger a mutating plan, such as opening Calendar, and confirm the UI enters `awaiting_confirm`.
18. Confirm `Approve`, nod, or voice "yes" executes the tool; `Deny`, shake, stem press, or voice "no" cancels it.
19. Keep `MCP tool` and `Shell tool` disabled and confirm those requests are rejected as disabled.
20. Add `~/Library/Application Support/cerberus/mcp-servers.json`, enable `MCP tool`, and confirm an MCP `tools/call` request runs only after approval while resource/prompt/OAuth discovery reads run read-only.
21. For an OAuth-protected Streamable HTTP MCP server, run `mcp.oauth.start`, complete the browser authorization, run `mcp.oauth.exchange`, then run `mcp.oauth.refresh` if a refresh token was issued and confirm later MCP HTTP calls attach the stored bearer token.
22. Enable `Shell tool`, request an allowlisted command such as `git status`, and confirm it routes through `ShellExecService.xpc` only after approval.
23. Test AirPods nod, shake, and stem press behavior separately from speech and model behavior.
24. Confirm the first `mail.search` call prompts for Mail Automation access, then returns subject/sender metadata without changing read status.

## Known Follow-Up

- `Scripts/build_app.sh` embeds `ShellExecService.xpc`; Developer ID signing and notarization still require local credentials.
- AirPods nod/shake classification has manual neutral-pose calibration and adjustable thresholds, but those thresholds still need real walking/noisy-environment tuning.
- Direct per-device speech routing is not implemented; `AVSpeechSynthesizer` on macOS uses the system output route, and the app only reports that route.
- Wake phrase uses live speech transcription, not a dedicated low-power keyword-spotting model.
- Native FoundationModels `Tool` integration is wired for read-only tools. Mutating tools remain on guided planning plus app-owned confirmation.
- Screen understanding is OCR-only because this SDK's FoundationModels prompt surface is text-only.
- MCP support is limited to stdio and Streamable HTTP tools/resources/prompts plus OAuth PKCE browser handoff and refresh-token rotation; automatic redirect capture is not implemented.
- Adapter training is not implemented; only prebuilt adapter loading is supported.
