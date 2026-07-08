# Competitive Roadmap Decision

Date: 2026-07-08
Status: Decision doc.

## Decision

[Inference] Cerberus should ship as a FOSS, local-first, user-visible macOS screen Q&A assistant before expanding into meeting notes, overlays, or memory. The competitive gap is not stealth. The gap is a trustworthy local Mac assistant that reads the user's own screen, answers quickly, refuses hidden high-stakes help, and exposes enough state for consent and audit.

## Inputs

This decision synthesizes:

- Cluely-style real-time assistant research.
- Meeting notetaker research.
- Voice-first macOS dictation research.
- Local capture and personal memory research.
- Local VLM provider plan.
- Product principles and consent policy.
- Security posture: screen-only tools, read-only execution, encrypted transcripts, audit logs, local-first defaults.
- Transparent overlay proposal.
- Live meeting mode feasibility.
- Open implementation issues.

## Ranked Directions

| Rank | Direction | Decision | Cost | Risk | Differentiation |
| --- | --- | --- | --- | --- | --- |
| 1 | Screen Q&A | Ship first | Medium | Medium | High |
| 2 | Local VLM provider support | Harden behind config | Medium-high | Medium-high | High |
| 3 | Transparent overlay | Prototype only as visible active state | Medium | High | Medium |
| 4 | Live notes | Evaluate after benchmark data | High | High | Medium |
| 5 | Local memory | Defer | High | Very high | Medium-high |

## Direction Notes

### 1. Screen Q&A

Decision: Ship first.

Why:

- Matches current architecture: explicit trigger -> SpeechAnalyzer -> Foundation Models -> read-only screen tools -> spoken/text answer.
- Uses existing local tool surface: `screen.snapshot`, `screen.ocr`, `screen.barcodes`, `screen.ui_elements`, and optional `screen.describe`.
- Competes on local reliability, clear boundaries, and inspectability instead of hidden assistance.
- Keeps storage and consent risk bounded.

Cost:

- Medium. Most code paths exist; target hardware validation, latency thresholds, and release docs remain.

Risk:

- Medium. Foundation Models, SpeechAnalyzer, ScreenCaptureKit, AirPods routing, and permission recovery still need real hardware validation.

Differentiation:

- High. Competitors tend to bundle cloud transcription, meeting memory, broad automation, or stealth. Cerberus can own local screen-specific help with visible state.

### 2. Local VLM Provider Support

Decision: Harden behind config after screen Q&A is stable.

Why:

- Adds value when OCR/UI geometry cannot answer visual questions.
- Keeps raw screenshot use optional and explicit.
- Supports local providers such as MLX-VLM, Ollama, llama.cpp, or localhost OpenAI-compatible servers.

Cost:

- Medium-high. Provider setup, runtime compatibility, fixture coverage, screenshot handling, and user docs need work.

Risk:

- Medium-high. VLM latency, hallucination, screenshot privacy, and non-local endpoint egress are not acceptable as silent defaults.

Differentiation:

- High if local quality passes benchmarks. Many screen assistants rely on cloud context; a local passive VQA path is a clearer FOSS differentiator.

### 3. Transparent Overlay

Decision: Prototype only as visible active state after product approval.

Why:

- Improves live status, cancellation, consent, and screen-read awareness.
- Helps compete with floating assistant UX without copying stealth.
- Supports meeting/screen-share clarity when designed to be captured normally.

Cost:

- Medium. Requires AppKit/SwiftUI window work, placement, accessibility, screen-share checks, and visual QA.

Risk:

- High. Overlay work can drift into hidden or not-captured behavior if product constraints are loose.

Differentiation:

- Medium. The useful part is visible, accessible status. The market already has overlays; Cerberus should differentiate by not hiding.

### 4. Live Notes

Decision: Evaluate after benchmark data; do not ship in v1.

Why:

- Meeting notes are market-proven, but crowded and consent-sensitive.
- Feasible local pipeline exists on paper: microphone transcript + screen OCR/UI/VLM context + Foundation Models answer/notes.
- Actual latency and AirPods/noisy-room accuracy are unverified.

Cost:

- High. Needs rolling transcript buffers, session state, consent UI, retention/delete/export controls, and combined benchmarks.

Risk:

- High. Consent, bystander audio, retention, note accuracy, and hidden coaching misuse are central product risks.

Differentiation:

- Medium. Local-first notes are useful, but meeting tools already compete heavily. Cerberus should enter only with a narrow "Session Notes" experiment.

### 5. Local Memory

Decision: Defer.

Why:

- Persistent memory changes Cerberus from an observer-only turn assistant into a sensitive archive of screens, voices, meetings, and bystander context.
- The safer later shape is "remember this explicit session", not "remember everything".

Cost:

- High. Needs retention policy, search, local indexing, encryption, export, deletion, UI, audits, and red-team coverage.

Risk:

- Very high. Always-on capture and memory can create surveillance, workplace policy, and third-party consent problems.

Differentiation:

- Medium-high. Local memory is valuable, but only after the base assistant has clear trust and deletion semantics.

## Recommended Next 3 Milestones

### Milestone 1: Screen Q&A Release Candidate

Goal: validate and release the current screen-only assistant without adding new product surfaces.

Implementation issues:

- [#28 Update stale GitHub issues after vision-only purge](https://github.com/gongahkia/cerberus/issues/28)
- [#3 Hardware validation](https://github.com/gongahkia/cerberus/issues/3)
- [#4 AirPods trigger quality](https://github.com/gongahkia/cerberus/issues/4)
- [#5 Speech and wake-word quality](https://github.com/gongahkia/cerberus/issues/5)
- [#6 Foundation Models and SDK work](https://github.com/gongahkia/cerberus/issues/6)
- [#8 UX, onboarding, and settings polish](https://github.com/gongahkia/cerberus/issues/8)
- [#9 Docs, demo, and release assets](https://github.com/gongahkia/cerberus/issues/9)
- [#1 Release gates](https://github.com/gongahkia/cerberus/issues/1)
- [#2 Open-source readiness](https://github.com/gongahkia/cerberus/issues/2)
- [#10 Tests and CI](https://github.com/gongahkia/cerberus/issues/10)

Exit criteria:

- Stale non-vision issue requirements removed.
- Target hardware validates permissions, screen tools, speech, AirPods, Foundation Models, audit, encryption, and fail-closed behavior.
- `swift test`, script lint/static checks, and release checks pass where credentials/hardware allow.
- README and validation docs show measured requirements, not assumptions.
- Release gate issues are either complete or explicitly blocked by credentials/manual approval.

### Milestone 2: Local VLM Beta

Goal: make passive screenshot VQA useful without making it a default dependency.

Implementation issues:

- [#6 Foundation Models and SDK work](https://github.com/gongahkia/cerberus/issues/6)
- [#3 Hardware validation](https://github.com/gongahkia/cerberus/issues/3)
- [#9 Docs, demo, and release assets](https://github.com/gongahkia/cerberus/issues/9)
- [#10 Tests and CI](https://github.com/gongahkia/cerberus/issues/10)

Exit criteria:

- At least one local provider passes generated and golden VLM fixtures on target hardware.
- `screen.describe` stays disabled until `local-vlm.json` validates.
- Non-local endpoints require explicit `allowNonLocalEndpoint` plus screenshot-egress disclosure.
- VLM answers stay passive: no GUI-agent behavior, no clicking, typing, navigation, or action plans.
- Docs list supported provider setup, latency ranges, failure modes, and deletion paths.

### Milestone 3: Visible Session Experiment

Goal: prototype the safest expansion path: visible overlay state plus opt-in local session notes.

Implementation issues:

- [#8 UX, onboarding, and settings polish](https://github.com/gongahkia/cerberus/issues/8)
- [#5 Speech and wake-word quality](https://github.com/gongahkia/cerberus/issues/5)
- [#6 Foundation Models and SDK work](https://github.com/gongahkia/cerberus/issues/6)
- [#3 Hardware validation](https://github.com/gongahkia/cerberus/issues/3)
- [#9 Docs, demo, and release assets](https://github.com/gongahkia/cerberus/issues/9)

Exit criteria:

- Live meeting mode benchmark plan has real speech/model/screen/VLM results.
- Overlay remains visible to the user and visible in normal screen sharing.
- Consent prompt and refusal paths cover meetings, interviews, exams, proctoring, and hidden capture.
- Session notes are explicit start/stop, local-first, encrypted only if retained, exportable, and deletable.
- No local memory beyond the active session.

## Deferrals

- General meeting notetaker: defer until Milestone 3 data passes.
- Always-on memory: defer beyond this roadmap.
- Cloud transcription/model fallback: defer; requires separate product and privacy review.
- GUI agent, app control, browser navigation, shell execution, MCP, calendar/reminder/mail/file actions: out of roadmap.
- Stealth, hidden overlays, screen-share bypass, proctoring evasion, and interview/exam coaching: rejected.

## Sources Checked

- `Docs/product-principles.md`
- `Docs/consent-and-misuse-policy.md`
- `Docs/security-model.md`
- `Docs/real-time-assistant-market-map.md`
- `Docs/meeting-notetaker-market-map.md`
- `Docs/voice-dictation-market-map.md`
- `Docs/local-capture-personal-memory-market-map.md`
- `Docs/local-vision-models.md`
- `Docs/transparent-overlay-ux-proposal.md`
- `Docs/live-meeting-mode-feasibility.md`
- `Docs/macos-validation.md`
- Open issues #1, #2, #3, #4, #5, #6, #8, #9, #10, #28
