# WriteIt

WriteIt is a local-first, open-source macOS utility for turning handwriting into text. Press a global shortcut, write with a mouse or tablet stylus, then send the recognized result to the text field that was focused when capture began.

## Source beta

WriteIt is currently distributed as a source-first beta for Apple Silicon. It is not signed or notarized, and this repository does not provide downloadable OCR models or configured cloud OCR providers.

## Features

- Bottom-of-screen handwriting capture with mouse, tablet, and pressure input
- On-device Apple Vision OCR with runtime-discovered Latin-language support
- English fallback when the selected local language is unavailable
- Paste, Accessibility replacement, or clipboard-only delivery
- Editable review, retry, cancellation, undo, and no-ink feedback
- Encrypted local history; new installs retain text only for seven days
- Optional OpenAI-compatible text cleanup; only recognized text is sent
- Optional local LaTeX or MathJax formatting for supported written mathematical phrases
- Deterministic flowchart export as ASCII, Mermaid, Excalidraw JSON, or SVG
- Optional AI diagram fallback with explicit image-and-text consent

## Privacy

Apple Vision recognition runs on-device. WriteIt does not collect screen context, URLs, clipboard contents, raw ink, or recognized text in diagnostics.

Structured diagnostic events contain fixed lifecycle codes only, stay local, and retain at most 200 events from the last seven days. Turn off **Retain diagnostic logs** to delete them immediately and prevent new retained events. Diagnostic export contains event codes and timestamps only; it excludes text, ink, screenshots, identifiers, and credentials.

Anonymous metrics are off by default. When enabled, fixed lifecycle codes are queued locally and are not sent by this build. Optional AI cleanup is also off by default; when enabled, it sends recognized text to the endpoint and model selected by the user. Optional AI diagram fallback is separately off by default; when enabled with current consent, it can send the rendered capture image and recognized text to that endpoint only after local diagram translation does not qualify. API keys stay in Keychain.

Cloud OCR and custom providers are catalogued as future, explicit-consent capabilities. They are not implemented in this build.

---

## Requirements

- macOS 15+
- Apple Silicon is the current supported development target
- Accessibility permission for the global shortcut and insertion

## Getting started

1. Build and open WriteIt.
2. Enable Accessibility when prompted.
3. Set a shortcut in Settings.
4. Focus a text field in another app.
5. Press the shortcut, write, then press it again to recognize.
6. Retry, review, or use the copied result if direct delivery is unavailable.

## Development

Build and run:

```sh
./script/build_and_run.sh
```

Run tests:

```sh
swift test
```

Verify a source-beta checkout on macOS with Xcode installed:

```sh
./script/verify_source_beta.sh
```

It builds and tests in temporary SwiftPM scratch paths, validates release attribution, and removes the paths without modifying `.build`. See [BUILD.md](BUILD.md) for release and notarization notes.

## Project direction

The active implementation plan is tracked in this repository’s GitHub issues. Current work includes verified model manifests, profile-scoped cloud consent, delivery compatibility testing, and privacy-preserving diagnostics/export.

## License

WriteIt is licensed under the [MIT License](LICENSE). Copyright © 2026 Gabriel Ong Zhe Mian.
