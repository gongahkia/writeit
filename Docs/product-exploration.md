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
