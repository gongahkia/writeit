# Architecture

```mermaid
flowchart TD
    User["User trigger\nmenu, hotkey, AirPods, wake phrase"] --> App["cerberusApp\nSwiftUI menu bar + AppModel"]
    App --> Core["cerberusCore"]
    Core --> Speech["Speech\nTranscriber + Speaker"]
    Core --> Model["Reasoning\nFoundation Models session"]
    Model --> NativeTools["Read-only native tools\ncalendar, reminders, mail, files, web, OCR, memory"]
    Model --> Plans["Guided tool plans"]
    Plans --> Confirm["ConfirmationGate\nbuttons, voice, nod/shake"]
    Confirm --> Registry["ToolRegistry"]
    Registry --> MutatingTools["Mutating tools\ncalendar.create, reminders.create, reminders.complete, music.control, app.control"]
    Registry --> MCP["MCP stdio / Streamable HTTP / OAuth"]
    Registry --> Shell["ShellTool"]
    Shell --> XPC["ShellExecService.xpc\nallowlisted command execution"]
    Core --> Storage["Local storage\nApplication Support + Caches"]
    Storage --> Encrypted["Encrypted transcripts + memory\nKeychain AES-GCM keys"]
    Storage --> Audit["Audit log\nhash chain + HMAC"]
    Storage --> Snapshots["Screen snapshots\nCaches/cerberus"]
    Core --> Bench["CLI tools\nbenchmarks, adapter export/eval, wake samples"]
```

`cerberusApp` owns UI state, permissions, user settings, and confirmation presentation. `cerberusCore` owns deterministic state machines, tool implementations, security gates, storage, MCP clients, speech/model wrappers, and CLI support. The packaged app embeds `ShellExecService.xpc`; release scripts build/sign the nested service before signing the parent app.
