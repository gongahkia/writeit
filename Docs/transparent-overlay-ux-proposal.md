# Transparent Overlay UX Proposal

Date: 2026-07-08
Status: Proposal only; do not implement UI until product principles approve an overlay surface.

Transparent means low visual weight, not hidden. The overlay should help the user understand active capture while staying visible on the user's display and in normal screen sharing.

## Product Rule

Cerberus may add a compact overlay only if it reinforces the existing product principles:

- Visible-to-user operation.
- Explicit trigger before microphone capture unless the user enables wake phrase.
- Menu bar state remains authoritative.
- Observer-only assistance; no clicking, typing, app control, shell execution, browser navigation, or data mutation.
- Local-first screen and speech processing by default.
- Refusal of hidden help for exams, interviews, proctoring, and third-party conversations.

## Non-Goals

- Hidden overlay.
- Screen-share bypass.
- Exam/interview stealth.
- Proctoring evasion.
- Window, Dock, task-switcher, process-list, or Activity Monitor hiding.
- Invisible live coaching for meetings, interviews, assessments, exams, or third-party conversations.
- API use whose product value depends on other people not seeing that Cerberus is active.

## Concept

Name: Visible Assist Strip.

Default state remains menu bar only. The strip appears after an explicit trigger and disappears after the turn completes, is canceled, or errors. It is a small translucent SwiftUI/AppKit surface with an opaque fallback for accessibility settings.

Placement:

- Default: top-right, below the menu bar, inset from screen edges.
- Alternate: bottom-center for users whose work is concentrated near the top-right.
- Never full-screen.
- Never over password fields when the active Accessibility element is identifiable as secure text input.

Visible states:

| State | Menu bar | Strip |
| --- | --- | --- |
| Idle | normal icon | hidden |
| Listening | red microphone tint | "Listening" plus mic indicator |
| Transcribing | red microphone tint | "Transcribing locally" |
| Reading screen | amber screen indicator | "Reading visible screen" |
| Thinking | blue spinner | "Preparing answer" |
| Speaking/answer | blue speaker indicator | short answer or "Speaking" |
| Needs permission | warning badge | missing permission and Settings action |
| Consent unclear | warning badge | concise consent question |
| Error/canceled | gray/error badge | one-line failure or canceled state |

Hotkeys:

- Command-Shift-L: listen, matching `CerberusApp` global command docs.
- Command-Period: cancel.
- Command-Shift-R: refresh permissions.
- Command-Comma: settings.
- Control-Option-Space: demo/manual trigger compatibility.
- Optional AirPods stem gesture: start/stop only when explicitly configured.

## ASCII Mockups

Menu bar state:

```text
idle:        [cerberus]
listening:   [cerberus mic:red]
screen read: [cerberus screen:amber]
answering:   [cerberus speaker:blue]
error:       [cerberus !]
```

Assist strip:

```text
+------------------------------------------------+
| CERBERUS  Listening                  mic red   |
| "what text is on my screen?"                   |
| Cmd-. cancel                 visible if shared |
+------------------------------------------------+
```

Compact screen-reading state:

```text
+-----------------------------------------------+
| CERBERUS  Reading visible screen     amber    |
| local OCR + Accessibility only                |
+-----------------------------------------------+
```

Consent interruption:

```text
+------------------------------------------------+
| CERBERUS  Consent unclear              !       |
| Are the other participants aware AI is active? |
| [Yes, continue] [No/unsure, stop]              |
+------------------------------------------------+
```

## Core Flow

```text
user trigger
  -> menu bar turns red
  -> strip appears as Listening
  -> silence timeout or stop gesture
  -> Transcribing locally
  -> optional transcript confirmation if confidence is low or consent context is unclear
  -> Reading visible screen if the request needs screen context
  -> Preparing answer
  -> Speaking/answer
  -> strip dismisses, menu bar returns idle
```

Cancel flow:

```text
Command-Period or AirPods stop gesture
  -> stop microphone
  -> stop pending screen read
  -> show Canceled briefly
  -> dismiss strip
```

Permission flow:

```text
request needs microphone, speech, accessibility, input monitoring, or screen recording
  -> missing permission detected
  -> menu bar warning badge
  -> strip shows missing permission and Settings action
  -> no capture until permission is granted
```

## Screen-Share Visibility

The overlay should be captured by ordinary display sharing and recording paths. Do not design a screen-share exclusion path, hidden window level, invisible process surface, or bypass mode.

Tradeoff: participants may see that Cerberus is active. This is acceptable and matches the product principles. If the user wants no one to see Cerberus, the correct behavior is to stop Cerberus, not hide it.

Design constraints:

- Do not use window-sharing exclusion as a product feature.
- Do not add "hide from screen sharing", "stealth", "undetectable", or "safe for proctoring" settings.
- In meeting/screen-share contexts, prefer a visible active badge and concise consent checks.
- If implementation later uses ScreenCaptureKit, test with normal display sharing and screen recording to confirm the strip remains visible.

## Privacy

The strip should expose active state without leaking more user content than needed.

Privacy choices:

- Show capture state even in compact mode.
- Allow redacted prompt text in compact mode, but keep the active microphone/screen state visible.
- Do not show full transcript by default when low confidence, when the active app appears sensitive, or when third-party consent is unclear.
- Keep local-first processing labels short and factual.
- Provide a visible stop/cancel action in every active state.

Tradeoff: showing a prompt or answer can reveal sensitive content on a shared screen. Redacted compact mode reduces content exposure while keeping capture visible.

## Distraction

The strip should be small, stable, and predictable.

Interaction choices:

- Fixed dimensions per size class so state changes do not resize the strip.
- Minimal animation; respect Reduce Motion.
- Auto-dismiss after a short answer unless pinned by the user.
- No decorative motion, gradients, or attention-seeking effects.
- Avoid covering menu extras, call controls, code editor cursors, password fields, or system permission prompts.

Tradeoff: persistent visibility adds visual load. Auto-dismiss and compact mode lower distraction without turning the feature into a hidden overlay.

## Accessibility

Accessibility requirements:

- VoiceOver labels for state, capture type, cancel, settings, and consent controls.
- Full keyboard operation for listen, cancel, settings, permission refresh, placement, and compact mode.
- Respect Reduce Transparency by switching to an opaque material or solid background.
- Respect Increase Contrast and Differentiate Without Color.
- Do not rely on color alone; pair red/amber/blue indicators with text and symbols.
- Support larger text without clipping by keeping short labels and stable layout.
- No hover-only controls.

Tradeoff: translucent UI can reduce readability. The accessible default should favor contrast and legibility over visual lightness.

## Implementation Gate

Do not implement until product approval covers:

- Whether an overlay is needed for v1.
- Exact default placement and compact/redacted behavior.
- Whether answers may appear in the strip or only in the menu bar panel.
- VoiceOver and keyboard test checklist.
- Screen-share test checklist.
- Consent-copy final review.

## Sources Checked

- `Docs/product-principles.md`
- `Docs/consent-and-misuse-policy.md`
- `Docs/ui-accessibility-review.md`
- `Docs/demo-script.md`
- `Docs/implementation-notes.md`
- Apple Human Interface Guidelines: Menu Bar, Accessibility, Materials
- Apple Accessibility features: Reduce Transparency, Increase Contrast, Differentiate Without Color
- Apple ScreenCaptureKit documentation
