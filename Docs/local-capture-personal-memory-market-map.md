# Local Capture And Personal Memory Market Map

Date: 2026-07-08

Scope: Local-first, ambient, or personal-memory assistants adjacent to Cerberus. This comparison uses public vendor claims and docs checked on the date above; it is not a hands-on benchmark of recall quality, transcription accuracy, latency, battery life, or security implementation.

## Summary

The market splits into four patterns:

- Desktop memory layers capture screens, app text, browser context, and sometimes audio into a searchable local timeline.
- OS-level recall captures periodic screen snapshots into a local encrypted store, but is platform-gated and policy-heavy.
- Wearables capture conversations and ambient context, usually with cloud transcription or companion apps.
- Knowledge-memory apps capture notes, code, links, and workflow context, then expose search/chat over that history.

[Inference] Cerberus should remain stateless screen Q&A for v1. Persistent memory is attractive, but it changes the product from an observer-only helper into a sensitive data store. The only plausible later path is opt-in, per-session local memory with visible capture state, retention controls, export, deletion, and no hidden third-party conversation capture.

## Comparison

| Product | Capture modality | Storage locality | Search / recall UX | Hardware dependencies | Subscription / pricing observed | Privacy controls | Deletion / export behavior | Mac relevance |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [Screenpipe](https://screenpipe.com/about) | Continuous desktop screen, app text, browser context, screen recording, and audio transcription | Local SQLite database and MP4 files by default; optional encrypted sync | Local timeline, search, chat, MCP/API, pipes, local model support | Desktop only; 8 GB RAM recommended; no special wearable | Hosted desktop app starts at $25/mo; Pro $50/seat/mo; Enterprise $150/seat/mo; core engine/CLI source-available | No account required for core app; local AI through Ollama; cloud models only if chosen | Export, delete, or back up data; configurable retention | Full macOS Apple Silicon and Intel support |
| [Limitless / Rewind](https://www.limitless.ai/) | Historical desktop/web recording and Pendant audio capture | Cloud service for existing recorded meetings/transcripts | Access to previously recorded meetings through 2026; no new desktop/web recording | Pendant no longer sold; Rewind desktop capture disabled | Existing customers moved to free Unlimited; no new Pendant sales | Official page says some regions lost service on 2025-12-05 | Account/data export and deletion remain available | Historical Mac reference only; current page says desktop/web recording no longer works |
| [Omi](https://www.omi.me/pages/product) | Wearable, phone, desktop, web, Apple Watch; screen and conversation capture claims | Can store conversations locally on phone or cloud; local mode and BYO/custom STT options are claimed | Search summaries, tasks, memories; Ask Omi; daily recaps; brain map; app marketplace | $89 Omi device; phone required for normal use; DevKit 2 adds 8 GB standalone recording but still needs app for transcription processing | Product page says subscription starts at $16/mo for unlimited cloud transcription; free on-phone transcription plus 1,200 cloud minutes/mo | Open-source hardware/software; encryption claims; docs describe self-host or secure cloud; consent warning for recording others | Product page claims easy export, item deletion, and wipe; privacy docs also describe deletion requests | Mac desktop, web, iOS, Apple Watch support |
| [Pieces](https://pieces.app/) | Workflow context, code, docs, chats, links, snippets, browser/editor activity | Local-first PiecesOS storage; cloud LLM requests use scoped context by default | Long-Term Memory, natural search, time-based queries, MCP/context for AI tools | Desktop service; macOS 13+, Windows, Linux; no wearable | Free Forever; Pro $18.99/mo or $169.99/year; Pro extends memory up to 9 months and removes model caps | No continuous sync or bulk upload per docs; data folder is local; cloud backup and cloud LLM calls are user-initiated/scoped | Delete local data by removing `com.pieces.os`; local folders can be backed up/copied | Strong Mac relevance for developer workflow memory |
| [Microsoft Recall](https://support.microsoft.com/en-us/windows/privacy/privacy-and-control-over-your-recall-experience) | Periodic screen snapshots with local processing and OCR | Local encrypted store on Copilot+ PC; keys protected through TPM/Windows Hello/VBS enclave | Timeline/search over snapshots; app/website filters; sensitive info filter | Windows-only Copilot+ PC, NPU-class hardware, Windows Hello | Bundled Windows feature; no separate subscription observed | Opt-in, off by default, pause/disable, taskbar/system-tray state, filters, sensitive info filtering | Delete snapshots, reset Recall, set storage/retention; EEA export if policy allows | No macOS support; useful OS-level privacy/control reference |
| [Bee](https://bee.computer/) | Wearable conversational capture, voice notes, places/tasks/patterns | Cloud/mobile service; product page claims audio is processed in real time and deleted immediately | Summaries, takeaways, to-dos, daily memories, search/chat over history | $49.99 Bee Pioneer; iOS/Apple Watch first; Android early access not actively supported; wearable with mic/button/LED | Device price observed; Premium monthly subscription is planned but details are forthcoming | LED active state; button start/stop; privacy notice covers voice patterns, geolocation, audio/video/call recordings categories and AI service providers | Product page claims permanent/immediate deletion controls; privacy notice says account termination deletes information after identity verification, subject to retained compliance/fraud records | iOS/Apple Watch adjacent; no Mac app found in checked pages |
| [Plaud](https://www.plaud.ai/) | Dedicated voice recorder hardware for in-person meetings, calls, and online meetings; Plaud Desktop requires device | Device/app/cloud processing; Private Cloud Sync optional | Transcripts, summaries, Ask Plaud, templates, export/share/integrations | Plaud Note/NotePin hardware $159-$189; Plaud Desktop requires device | Starter free 300 min/mo; Pro $8.33/mo annual for 1,200 min/mo; Unlimited $19.99/mo annual or $29.99/mo monthly; Team $20/user/mo annual | Trust page lists encryption/compliance controls; Private Cloud Sync controls whether data remains stored after processing | If Private Cloud Sync is off, server copies are deleted after processing; if on, stored encrypted data is deleted by explicit request | Mac/PC desktop app exists but hardware-gated |
| [Apple Intelligence](https://www.apple.com/apple-intelligence/) | Platform assistant context across supported Apple apps and device content; not an always-on capture timeline | On-device processing plus Private Cloud Compute for larger requests | Siri/Apple Intelligence can use personal context within supported apps; no vendor page checked describes a user-visible all-day capture timeline | Compatible Apple Intelligence devices; M-series Mac requirement path applies | Bundled platform feature; no separate subscription observed | On-device processing privacy model; support page says turning off removes on-device models | No unified assistant-memory export found in checked pages; app data remains governed by each app/storage system | Native Mac baseline and privacy expectation |

## Cerberus Differentiation

- Stateless by default: Cerberus currently avoids building a high-value archive of screens, voices, meetings, and bystander data.
- Explicit trigger: Competitors sell always-on memory. Cerberus should keep user-triggered capture as the default UX.
- Local and inspectable: If memory is added later, use local encrypted storage with a plain export path before any sync/integration.
- Consent boundary: Ambient audio and wearable products raise bystander consent risk. Cerberus should require explicit consent for meetings and third-party conversations.
- Narrow recall: Screenpipe/Pieces prove demand for local workflow recall, but Cerberus can start with a smaller primitive: "remember this session" instead of "remember my life".
- No hidden automation: Recall/memory should not create a covert coaching or surveillance layer. Keep observer-only limits from the product principles.

## Recommendation

Do not add durable memory to v1. Keep Cerberus as stateless screen Q&A plus explicit local speech capture.

Add opt-in local memory later only if all of these are implemented first:

- per-session enablement,
- visible capture indicator,
- participant-consent gate for conversations,
- encrypted local store,
- retention limit with auto-delete,
- one-command delete all,
- export in a documented local format,
- no cloud sync by default,
- no third-party integrations before storage/deletion semantics are stable,
- refusal for interviews, exams, proctoring, hidden coaching, and non-consensual third-party monitoring.

[Inference] The strongest later product shape is not "Cerberus remembers everything". It is "Cerberus can temporarily remember this explicit work session and answer questions about it locally".

## Sources Checked

- Screenpipe about: https://screenpipe.com/about
- Screenpipe privacy: https://screenpipe.com/privacy
- Limitless current service page: https://www.limitless.ai/
- Omi product: https://www.omi.me/pages/product
- Omi homepage: https://www.omi.me/
- Omi docs introduction: https://docs.omi.me/doc/get_started/introduction
- Omi setup: https://docs.omi.me/onboarding/omi
- Omi privacy: https://docs.omi.me/doc/info/Privacy
- Omi DevKit 2: https://docs.omi.me/doc/hardware/DevKit2
- Pieces homepage: https://pieces.app/
- Pieces privacy/security: https://docs.pieces.app/products/privacy-security-your-data
- Pieces downloads: https://docs.pieces.app/products/desktop/download
- Pieces paid plans: https://docs.pieces.app/products/paid-plans
- Microsoft Recall privacy/control: https://support.microsoft.com/en-us/windows/privacy/privacy-and-control-over-your-recall-experience
- Microsoft Recall management/export: https://learn.microsoft.com/en-us/windows/client-management/manage-recall
- Bee homepage: https://bee.computer/
- Bee Pioneer: https://bee.computer/bee-pioneer
- Bee privacy notice: https://bee.computer/privacy
- Amazon Bee update: https://www.aboutamazon.com/news/devices/bee-amazon-wearable-ai-device-new-features
- Plaud homepage: https://www.plaud.ai/
- Plaud pricing: https://www.plaud.ai/pages/plaud-ai-plan-pricing
- Plaud data handling: https://support.plaud.ai/hc/en-us/articles/49922008621337-How-do-you-handle-my-data-after-transcription
- Plaud trust: https://www.plaud.ai/pages/trust
- Apple Intelligence: https://www.apple.com/apple-intelligence/
- Apple Intelligence support: https://support.apple.com/en-us/121115
