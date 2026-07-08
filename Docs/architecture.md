# Architecture

```text
User trigger
  menu / hotkey / AirPods / wake phrase
        |
        v
cerberusApp
  SwiftUI menu bar, permissions, settings, speech lifecycle
        |
        v
cerberusCore
  speech, state machine, model wrapper, audit, encrypted transcripts
        |
        v
Foundation Models
  direct answer or typed screen-read plan
        |
        v
ToolRegistry
  screen.snapshot | screen.ocr | screen.barcodes | screen.ui_elements
        |
        v
ScreenCaptureKit / Vision / Accessibility
        |
        v
spoken answer + local transcript/audit
```

`cerberusApp` owns UI state, permissions, user settings, and voice/speech presentation. `cerberusCore` owns deterministic state machines, screen-reading tools, prompt-boundary escaping, audit signing, encrypted transcript storage, and CLI support.

The shipped app is observer-only: it captures screen context, extracts text/barcodes/UI geometry locally, and answers questions. It does not click, type, open apps, navigate browsers, run shell commands, call MCP tools, or mutate Calendar/Reminders/Finder/Music state.
