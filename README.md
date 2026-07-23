# WriteIt

WriteIt is a local-first handwriting-to-text utility for macOS. Press a shortcut, write with a mouse or stylus, then insert the recognized text into the previously focused text field.

## Requirements

- macOS 15 or later
- Accessibility permission for the global shortcut and direct insertion
- English handwriting in the current local OCR pipeline

## Install

Signed releases will be published on the [Releases page](https://github.com/gongahkia/writeit/releases). Until the first release is available, build WriteIt from source.

## Use

1. Enable Accessibility in WriteIt.
2. Press the configured shortcut to open the writing surface.
3. Write, then press the shortcut again to recognize and insert.
4. If no eligible text field is available, WriteIt copies the result to the clipboard.

The default result mode inserts text and offers a brief Undo action. Review and clipboard-only modes are available in Settings.

## Privacy

Handwriting recognition uses Apple Vision locally. Capture history is encrypted on the Mac and can be disabled or auto-deleted. Optional AI cleanup sends recognized text, not ink, to the OpenAI-compatible provider configured by the user.

The model catalog can store a compiled Core ML handwriting model locally; Apple Vision remains the active recognizer until the enhanced decoder is implemented.

## Build from source

```sh
./script/build_and_run.sh
```

See [BUILD.md](BUILD.md) for tests, Developer ID signing, and notarization.
