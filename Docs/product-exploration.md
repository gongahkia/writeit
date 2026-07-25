# Product Exploration

## iOS Companion

Decision: keep any iOS companion as a separate project.

Rationale:

- The current app is a macOS menu bar utility with macOS-only APIs: SpeechAnalyzer, Foundation Models, ScreenCaptureKit, Accessibility, Input Monitoring, Screen Recording, and menu bar state.
- Sharing a product target now would couple iOS release, entitlement, and privacy review work to the macOS v1 release gates.
- A companion is only useful after target-hardware validation proves the macOS AirPods workflow needs a second-screen setup, push notification, or remote trigger surface.

Allowed future scope:

- A separate iOS repo or package can consume a narrow sync contract, such as setup state, validation results, or a remote trigger token.
- The macOS app should expose that contract only after local permission, audit, and deletion semantics are designed.

Not in scope for macOS v1:

- Shared SwiftUI app target.
- Cross-device transcript sync.
- iCloud-backed assistant memory sync.
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

## Cloud Model Fallback

Decision: do not add a cloud model fallback unless local Foundation Models quality is insufficient and the product privacy scope changes.

Rationale:

- The project positioning is local-first: planning, transcripts, screen OCR, audit logs, and adapter data stay on device by default.
- A cloud fallback would change data-flow guarantees for speech transcripts, screen-derived text, visible file names, and screen-tool outputs.
- Cloud routing would require new UX for consent, per-request disclosure, retention expectations, deletion semantics, network failure states, and audit entries.

Minimum gates before reconsidering:

- Hardware benchmark results showing local model failure modes that cannot be fixed with tool schemas, prompts, adapter data, or app-specific context.
- A privacy design that separates cloud-eligible prompts from never-send local data.
- Settings controls for default-off cloud use, per-request approval, and complete disablement.
- Audit fields recording provider, model family, prompt category, and whether sensitive local context was excluded.
- Updated threat model and release notes before implementation.

Fallback shape if approved later:

- Default off.
- Explicit user confirmation before the first cloud request.
- No raw screen images, audit logs, or transcript history in cloud prompts.
- Prefer short tool-planning prompts over broad conversation dumps.

Rejected for now:

- Silent fallback when local model is unavailable.
- Cloud summarization of unfiltered tool payloads.
- Cloud storage or sync for transcripts or validation artifacts.
