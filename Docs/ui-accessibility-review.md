# UI Accessibility Review

Review date: 2026-06-19

## Keyboard Access

- Global commands expose the primary menu bar actions from `CerberusApp`: listen with Command-Shift-L, cancel with Command-Period, refresh permissions with Command-Shift-R, and open Settings with Command-Comma.
- The status panel uses standard SwiftUI controls for keyboard traversal: segmented picker tabs, buttons, toggles, text fields, text editor, disclosure groups, sliders, and pickers.
- Session controls keep explicit text labels for Listen, Run, Cancel, Approve, and Deny.
- Settings controls are keyboard-reachable through native Toggle, Picker, DisclosureGroup, TextField, Slider, and Button controls.

## Label Coverage

- Icon-only history buttons expose labels for exporting, deleting, and refreshing transcript history.
- Icon-only audit buttons expose labels for clearing and refreshing tool calls.
- Icon-only permission buttons expose labels for refreshing permission status and requesting each permission.
- Icon-only settings buttons expose labels for refreshing model, screen snapshot, speech route, and gesture threshold state.
- Icon-only app-data buttons expose labels for revealing local data locations.

## Follow-Up Scope

This review covers source-level keyboard and accessibility-label coverage. It does not replace a VoiceOver pass on target macOS hardware.
