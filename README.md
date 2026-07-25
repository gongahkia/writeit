# WriteIt

WriteIt is a local-first macOS utility for turning handwriting into text. Press a global shortcut, write with a mouse or tablet stylus, and send the result to the text field that was focused when capture began.

## Status

WriteIt is a source-first beta, currently developed and tested on Apple Silicon. It is not yet signed or notarized, and it does not currently provide downloadable OCR models or configured cloud OCR providers.

## Requirements

- macOS 15+
- Apple Silicon is the current supported development target
- Accessibility permission for the global shortcut and insertion

## What it does

- Bottom-of-screen handwriting surface with mouse and tablet pressure input
- Local Apple Vision OCR with runtime-discovered Latin-language capability
- English fallback when a selected local language is unavailable
- Paste, Accessibility replacement, or clipboard-only delivery
- Editable review, cancellation, retry, and no-ink feedback
- Encrypted local history; new installs keep text only for seven days
- Optional OpenAI-compatible OCR cleanup; only recognized text is sent

## Privacy

Apple Vision recognition runs on-device. WriteIt does not collect screen context, URLs, clipboard contents, raw ink, or recognized text in diagnostics.
Structured diagnostic events contain fixed lifecycle codes only, stay local, and retain at most 200 events from the last seven days.
Turn on “Do not retain diagnostic logs” to delete them immediately and prevent new retained events.
Diagnostics export contains event codes and timestamps only; it excludes text, ink, screenshots, identifiers, and credentials.
Anonymous metrics are off by default; when enabled, fixed lifecycle codes are queued locally and are not sent by this build.

Optional AI cleanup is off by default. When enabled, it sends recognized text to the endpoint and model selected by the user. API keys stay in Keychain.

Cloud OCR and custom providers are catalogued as future, explicit-consent capabilities. They are not implemented in this build.

## Build and run

```sh
./script/build_and_run.sh
```

Run tests with:

```sh
swift test
```

See [BUILD.md](BUILD.md) for the current packaging notes.

## Use

1. Open WriteIt and enable Accessibility.
2. Set a shortcut in Settings.
3. Focus a text field in another app.
4. Press the shortcut, write, then press it again to recognize.
5. Retry, review, or use the copied result if direct delivery is unavailable.

## Development direction

The active implementation plan is tracked in this repository’s GitHub issues. The next substantial areas are verified model manifests, profile-scoped cloud consent, delivery compatibility testing, and privacy-preserving diagnostics/export.

## License

The intended license is MIT; the license file has not yet been added.
