# Troubleshooting

## Foundation Models Unavailable

Open Settings and refresh the Foundation Models status row. If it reports ineligible hardware, use an Apple Intelligence-capable Apple Silicon Mac. If Apple Intelligence is disabled, enable it in System Settings. If the model is not ready, leave the Mac online and unlocked until the system model finishes preparing.

## SpeechAnalyzer Unavailable

Confirm macOS 26 and Xcode 26 are installed, then grant Microphone and Speech Recognition access. If transcription still fails, run `Scripts/benchmark_speech.sh --seconds 8 --expected "hey cerberus open calendar"` from the same account to capture the local error path.

## Screen Recording Denied

Grant Screen Recording in System Settings, then relaunch cerberus. `screen.snapshot` and `screen.ocr` fail closed until `CGPreflightScreenCaptureAccess()` reports access.

## Mail Automation Denied

Grant Automation access for Mail in System Settings after the first `mail.search` prompt. The Mail tool is read-only and returns subject/sender metadata; denied Automation prevents Mail Apple Events.

## Music Automation Denied

Grant Automation access for Music in System Settings after the first Music prompt. `music.now_playing` is read-only; `music.control` remains confirmation-gated after Automation is granted.

## MCP OAuth Failures

Check `~/Library/Application Support/cerberus/mcp-servers.json` for the server URL, scopes, client metadata, and explicit headers. Explicit `headers.Authorization` overrides stored OAuth tokens. Delete the related Keychain token if refresh-token rotation or stale credentials block authorization.

## Shell XPC Connection Failures

Build the packaged app with `Scripts/build_app.sh`, then confirm `Contents/XPCServices/ShellExecService.xpc` exists inside `.dist/cerberus.app`. Run `Scripts/release_check.sh dev-id` after signing; the app-side shell tool fails closed when the XPC service is missing or rejects a command.
