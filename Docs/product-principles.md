# Product Principles

Date: 2026-07-08

Cerberus is a FOSS, local-first macOS personal assistant for understanding the user's own screen. It is designed to stay out of the user's way, not out of other people's sight.

## What "Invisible" Means

Allowed meaning:

- Unobtrusive menu bar utility.
- No main window by default.
- Local-first screen and speech processing.
- Explicit trigger before microphone capture, unless the user enables the wake phrase.
- Small visible status surface with active microphone state.

Rejected meaning:

- Hidden from screen sharing, proctoring tools, task switchers, process lists, meeting participants, interviewers, exam monitors, or bystanders.
- Undetectable live coaching for interviews, exams, assessments, meetings, or third-party conversations.
- Any feature whose product value depends on another person not knowing Cerberus is active.

## Principles

1. FOSS over mystery
   - Public claims should be inspectable in code and docs.
   - Avoid dark-pattern language such as "undetectable", "secret", "cheat", "stealth", or "bypass".

2. Local-first by default
   - Foundation Models, SpeechAnalyzer, Vision OCR/barcodes, Accessibility reads, transcripts, audit logs, and screen snapshots stay local by default.
   - Cloud or non-local model paths require explicit, documented opt-in and must not receive raw local context silently.

3. User-visible operation
   - Microphone and screen-capture behavior must be visible in the app surface.
   - The app should be quiet and compact, but not deceptive.

4. Observer-only assistance
   - Cerberus observes and answers; it does not click, type, open apps, run commands, navigate browsers, invoke MCP tools, or mutate user data.
   - Screen-reading tools must remain read-only and fail closed when permissions are missing.

5. Consent-bound audio and meetings
   - Meeting notes and summaries are acceptable only when participants know AI capture is active and the relevant host, workplace, school, or platform policy allows it.
   - If consent is unclear, Cerberus should ask one concise question before proceeding.

6. No hidden high-stakes help
   - Cerberus must refuse hidden help for exams, homework, coding assessments, live interviews, hiring screens, proctoring, and professional evaluations.
   - It may support private rehearsal, study, mock interview practice, and self-review outside live assessment settings.

7. Minimal retention
   - Store only what the feature needs.
   - Keep transcripts encrypted, audit logs tamper-evident, screen snapshots pruned, and deletion paths documented.

8. No stealth arms race
   - Do not compete on screen-share invisibility, process hiding, browser-detection bypass, proctoring evasion, or covert overlays.
   - Compete on local reliability, low latency, accessibility, inspectability, and clear boundaries.

## Public Positioning

Use:

- FOSS local-first macOS screen-reading assistant.
- Unobtrusive menu bar assistant.
- User-visible local screen Q&A.
- Observer-only accessibility and productivity aid.

Do not use:

- Undetectable assistant.
- Invisible interview copilot.
- Hidden screen-share overlay.
- Proctoring-safe exam helper.
- Secret meeting coach.
