# Troubleshooting

## Foundation Models Unavailable

Open Settings and refresh the Foundation Models status row. If it reports ineligible hardware, use an Apple Intelligence-capable Apple Silicon Mac. If Apple Intelligence is disabled, enable it in System Settings. If the model is not ready, leave the Mac online and unlocked until the system model finishes preparing.

## SpeechAnalyzer Unavailable

Confirm macOS 26 and Xcode 26 are installed, then grant Microphone and Speech Recognition access. If transcription still fails, run `Scripts/benchmark_speech.sh --seconds 8 --expected "hey cerberus what text is on my screen"` from the same account to capture the local error path.

## Screen Recording Denied

Grant Screen Recording in System Settings, then relaunch cerberus. `screen.snapshot`, `screen.ocr`, and `screen.barcodes` fail closed until `CGPreflightScreenCaptureAccess()` reports access.

## Accessibility Denied

Grant Accessibility in System Settings, then relaunch cerberus. `screen.ui_elements` fails closed until `AXIsProcessTrusted()` reports access.
