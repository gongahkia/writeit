# Implementation Notes

These notes capture the current interpretation of `IDEA.md` so implementation choices stay explicit.

## Product Shape

cerberus is a hands-free macOS assistant shell, not a general chatbot. The model should plan, summarize, classify, and choose typed tools. Real work should happen in audited tools that interact with macOS state.

## MVP Order

1. Build the menu bar app and state machine.
2. Add deterministic triggers, starting with a manual menu trigger and then AirPods motion/media-key triggers.
3. Add speech input and spoken output.
4. Add Foundation Models planning.
5. Add a small, read-default tool surface.
6. Add confirmation, audit logs, and shell isolation before enabling mutating tools.

## Current Platform Assumptions

- Foundation Models supports on-device sessions, guided generation, and tool calling on Apple Intelligence-capable systems.
- SpeechAnalyzer and SpeechTranscriber are macOS 26 APIs for live and recorded transcription.
- CMHeadphoneMotionManager can stream AirPods motion on macOS for supported headphones.
- AirPods head gestures are also used by Siri/system features, so custom nod detection needs calibration and false-positive testing.
- Stem press interception is best treated as experimental because it overlaps with media controls.
