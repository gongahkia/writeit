# macOS Validation Checklist

This repository was scaffolded in a Linux workspace without Swift or Apple's SDK. Validate the implementation on a Mac that matches the project requirements.

## Required Environment

- macOS Tahoe 26 or later
- Xcode 26 or later
- Apple Silicon Mac with Apple Intelligence enabled
- AirPods with headphone motion support for gesture tests

## Build Checks

1. Open the package in Xcode 26.
2. Confirm `Package.swift` resolves with the macOS 26 platform setting.
3. Build the `cerberus` executable product.
4. Run the `cerberusCoreTests` test target.
5. Check all warnings from Swift 6 concurrency and macOS availability annotations.

## Runtime Checks

1. Launch the menu bar app and confirm the status item appears without a main window.
2. Request Microphone and Speech Recognition permissions.
3. Press `Listen`, speak a short request, then press `Run`.
4. Confirm SpeechAnalyzer transcribes into the request field.
5. Confirm Foundation Models returns either a direct spoken response or a typed tool plan.
6. Trigger a read-only tool request, such as "what is playing in Music?" or "search my files for README".
7. Confirm `~/Library/Application Support/cerberus/audit.log` records tool calls with a hash chain.
8. Trigger a mutating plan, such as opening Calendar, and confirm the UI enters `awaiting_confirm`.
9. Confirm `Approve` executes the tool and `Deny` cancels it.
10. Test AirPods nod, shake, and stem press behavior separately from speech and model behavior.

## Known Follow-Up

- Package Manager organizes source, but shipping a notarized menu bar `.app` needs an Xcode app target or equivalent packaging step.
- Shell execution defaults to dry-run and is not registered in the ambient tool catalog.
- The shell XPC service is represented by entitlements and policy but not yet implemented as a separate XPC target.
- AirPods nod/shake thresholds are initial values and need real walking/noisy-environment calibration.
