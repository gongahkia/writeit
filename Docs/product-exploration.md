# Product Exploration

## iOS Companion

Decision: keep any iOS companion as a separate project.

Rationale:

- The current app is a macOS menu bar utility with macOS-only APIs: SpeechAnalyzer, Foundation Models, ScreenCaptureKit, Accessibility, EventKit desktop permissions, Apple Events, XPC shell execution, and menu bar state.
- Sharing a product target now would couple iOS release, entitlement, and privacy review work to the macOS v1 release gates.
- A companion is only useful after target-hardware validation proves the macOS AirPods workflow needs a second-screen setup, push notification, or remote trigger surface.

Allowed future scope:

- A separate iOS repo or package can consume a narrow sync contract, such as setup state, validation results, or a remote trigger token.
- The macOS app should expose that contract only after local permission, audit, and deletion semantics are designed.

Not in scope for macOS v1:

- Shared SwiftUI app target.
- Cross-device transcript sync.
- iCloud-backed memory sync.
- Remote tool execution from iOS.

## Non-AirPods Trigger Surfaces

Decision: do not add non-AirPods trigger surfaces unless AirPods validation is weak.

Rationale:

- Current v1 interaction design depends on explicit local triggers, menu bar state, optional wake phrase, and AirPods gestures.
- More trigger surfaces increase accidental activation risk and make permission recovery harder to validate.
- AirPods validation must first quantify false positives, false negatives, disconnect behavior, speech latency, and confirmation reliability.

Candidate fallbacks if AirPods validation fails:

- Keyboard-only global hotkey improvements.
- Menu bar quick actions.
- Wake phrase with stricter confidence thresholds.
- Stream Deck or Shortcuts trigger that only starts listening, never executes tools directly.

Required gates before adding a fallback:

- A validation summary showing which AirPods failure mode the fallback addresses.
- Updated audit semantics for trigger source.
- Updated cancellation semantics for accidental activation.
- A manual QA matrix covering the new trigger alongside microphone, wake phrase, and confirmation flows.

Rejected for now:

- Always-on non-AirPods microphone trigger.
- Remote trigger from another device.
- Trigger surfaces that bypass visible menu bar state.
