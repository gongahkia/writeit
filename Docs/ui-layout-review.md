# UI Layout Review

Review date: 2026-06-19

## Long Paths

- App data paths render in monospaced caption text with one-line middle truncation.
- Screen snapshot status is capped to two lines, and the full latest-path value remains available through the Open latest action.

## Long Tool Names

- The enabled action summary uses wrapping text with vertical fixed sizing so the settings panel can expand downward instead of clipping the full list.
- Tool allowlist rows use monospaced caption names and cap capability copy to two lines.
- Tool confirmation rows use the same monospaced caption names and two-line capability cap.

## Long Status Text

- Foundation Models status, adapter status, privacy lock, speech route, wake monitor, and screen snapshot status use two- or three-line caps in the Settings panel.
- Transcript and audit rows cap long request, response, and payload text to bounded line counts.

## Follow-Up Scope

This review covers source-level layout handling for long strings. It does not replace rendered screenshot review at multiple window sizes.
