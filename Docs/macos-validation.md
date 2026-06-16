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
2. Request Microphone and Speech Recognition permissions.
3. Press `Listen`, speak a short request, then wait 1.5 seconds or press `Run`.
4. Confirm SpeechAnalyzer transcribes into the request field and silence moves to reasoning.
5. Confirm Control-Option-Space starts listening while the app is not focused.
6. Confirm Foundation Models returns either a direct spoken response or a typed tool plan.
7. Trigger a read-only tool request, such as "what is playing in Music?" or "search my files for README".
8. Confirm tool payloads are summarized into a useful spoken response.
9. Confirm `~/Library/Application Support/cerberus/audit.log` records tool calls with a hash chain.
10. Confirm `~/Library/Application Support/cerberus/transcripts.jsonl.enc` is written and not plaintext.
11. Ask cerberus to remember a preference and confirm `~/Library/Application Support/cerberus/memory.jsonl.enc` is written and not plaintext.
12. Trigger a mutating plan, such as opening Calendar, and confirm the UI enters `awaiting_confirm`.
13. Confirm `Approve`, nod, or voice "yes" executes the tool; `Deny`, shake, or voice "no" cancels it.
14. Test AirPods nod, shake, and stem press behavior separately from speech and model behavior.

## Known Follow-Up

- Package Manager organizes source, but shipping a notarized menu bar `.app` needs an Xcode app target or equivalent packaging step.
- Shell execution defaults to dry-run and is not registered in the ambient tool catalog.
- `Scripts/build_app.sh` embeds `ShellExecService.xpc`; Developer ID signing and notarization still require local credentials.
- AirPods nod/shake classification has a manual neutral-pose calibration action, but thresholds still need real walking/noisy-environment tuning.
- Native FoundationModels `Tool` integration is wired for read-only tools. Mutating tools remain on guided planning plus app-owned confirmation.
