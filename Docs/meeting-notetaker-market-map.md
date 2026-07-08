# Meeting Notetaker Market Map

Date: 2026-07-08

Scope: AI meeting notetakers adjacent to Cerberus but safer than stealth answer overlays. The comparison uses public vendor claims and pricing pages checked on the date above; it is not a hands-on word-error-rate or latency benchmark.

## Summary

Meeting notetakers split into two patterns:

- Bot-based systems join calls as a participant, usually making capture visible to the meeting platform and participants. They tend to offer stronger admin, sharing, CRM, analytics, and recording workflows.
- Bot-free systems capture device, browser, or extension audio without joining the meeting. They reduce meeting clutter and often feel closer to Cerberus, but they shift consent and disclosure responsibility onto the user.

Cerberus can differentiate by staying local-first, user-visible, observer-only, and consent-bound. The market gap is not another cloud meeting memory. The useful opening is a macOS-local screen/audio helper for explicit, first-party notes with no bot, no hidden coaching, encrypted local transcripts, and clear deletion.

## Comparison

| Product | Bot / no-bot mode | Audio capture | Transcript quality signal | Summaries, action items, search | Privacy / storage posture | Pricing observed | macOS support |
| --- | --- | --- | --- | --- | --- | --- | --- |
| [Granola](https://www.granola.ai/) | Bot-free; does not join the meeting | Desktop background transcription; iOS uses temporary cached audio per security docs | Vendor positions it as rich searchable meeting memory; no hands-on WER checked | Briefs before meetings, notes during meetings, searchable history after meetings | [Security page](https://www.granola.ai/security) says no stored meeting audio, encrypted AWS storage, private notes until shared, deletion request path | [Business $14/user/mo](https://www.granola.ai/pricing); free download | [Inference] Mac support from desktop download/security docs; iOS app |
| [Fathom](https://www.fathom.ai/) | Bot or no-bot | Captures meetings and produces post-call summaries | Vendor emphasizes instant AI summaries and call search, not a public WER metric | Summaries, clips/playlists, action items, conversational assistant, key-topic monitoring | Cloud meeting data connected to ChatGPT/Claude workflows; needs team policy review | [Premium $16-$20/user/mo; Team $15-$19/user/mo](https://www.fathom.ai/pricing) depending billing | Browser/meeting integrations; no specific native Mac requirement in checked page |
| [Fellow](https://fellow.ai/) | Bot participant for Fellow Note Taker; help page also references botless recording and Zoom RTMS articles | Note Taker joins conferencing link and sends audio to transcription partners | Claims AI transcription and action items; pricing page lists 99-language transcription | Agenda, transcript, summary, action items, templates, CRM fields, org analytics | Says AI is not trained on user data; Note Taker article describes participant visibility, encryption, retention/deletion controls, voiceprints, and enterprise deletion | [Free; Team $7/user/mo annual; Business $15/user/mo annual; Enterprise $25/user/mo annual](https://fellow.ai/pricing) | Web app, meeting integrations; App Store listing exists |
| [Read AI](https://www.read.ai/) | Bot / agent plus app workflows | Meeting transcripts, reports, audio/video playback on higher tier | 20+ languages, summaries across meetings/email/messaging; no WER checked | Summaries, transcription, search, topic readouts, meeting coach, enterprise search | [Privacy center](https://www.read.ai/account-and-privacy-center) supports account lookup, deletion, report deletion request, and meeting opt-out | [Free 5 meetings/mo; Pro $19.75/user/mo annual; Enterprise $29.75/user/mo annual; Enterprise+ $39.75/user/mo annual](https://www.read.ai/plans-pricing) | Windows, macOS, Android, iOS apps listed on pricing page |
| [Fireflies.ai](https://fireflies.ai/) | Mostly bot/service model across meeting platforms, plus app/extension surfaces | Zoom, Google Meet, Teams and more; uploads; desktop/mobile apps | 100+ languages, real-time notes/live transcription, AskFred assistant | Transcription, summaries, search, AskFred, action items, analytics, CRM integrations | Public positioning emphasizes GDPR/SOC2; storage minutes/seat are part of pricing | [Free; Pro $10/user/mo annual; Business $19/user/mo annual; Enterprise $39/user/mo annual](https://fireflies.ai/pricing) | Desktop app, mobile apps, Chrome extension |
| [Otter.ai](https://otter.ai/) | AI Meeting Agent can auto-join meetings | Zoom, Microsoft Teams, Google Meet, in-app recordings, uploads | Live transcription, speaker identification, multi-language support; no WER checked | AI chat across meetings, workflows, summaries, search, action items, integrations | [Privacy policy](https://otter.ai/privacy-policy) covers personal information handling; product creates stored meeting transcripts/notes | [Basic free; Pro $8.33-$16.99/user/mo; Business $19.99-$30/user/mo](https://otter.ai/pricing) depending billing/promo | Mac and Windows downloads; iOS/Android |
| [Tactiq](https://tactiq.io/) | Bot-free Chrome extension; no bot joins call | Captures live browser meeting transcript | 60+ languages, speaker identification, live transcript; no WER checked | Live summaries, action items, Ask AI, previous summaries | Chrome Web Store and pricing mention privacy/security controls; Business has data retention and SAML/SSO | [Free; Pro A$11.42/user/mo annual; Team A$23.17; Business A$44.25](https://tactiq.io/buy) | Chrome extension for Google Meet, Zoom, Teams; Mac via Chrome |
| [Bluedot](https://www.bluedothq.com/) | Bot-free extension/desktop/mobile; no meeting bot | Browser, desktop, phone, in-person, imports | Claims high accuracy for technical terms, to-dos, abbreviations, speaker ID; 100+ languages on App Store copy | Summaries, action items, AI chat, clips, comments, CRM/ATS sync, searchable transcripts | Public site recommends informing participants; pricing includes custom retention on Business | [Free 5 lifetime meetings; Basic $14/user/mo annual; Pro $20; Business $32](https://www.bluedothq.com/pricing) | Chrome extension, Mac/Windows desktop, iOS/Android, Apple Watch |
| [Jamie](https://www.meetjamie.ai/en) | Bot-free | Online, hybrid, offline meetings; no bot joins | 99+ languages, speaker recognition and memory; no WER checked | Structured notes, transcripts, action items, Ask AI, integrations | Claims GDPR compliance, EU hosting, no model training on customer data; pricing lists consent email/custom consent notification | [Free; Plus EUR21/mo annual; Pro EUR39/mo annual; Team EUR33/seat/mo annual](https://www.meetjamie.ai/pricing) | App download, iPhone; online/offline platform coverage |

## Differentiation Gaps For Cerberus

- Local-first/offline: Most competitors make cloud meeting records central. Cerberus can keep transcripts, screen context, and audit logs local by default, with no silent cloud fallback.
- Consent-first bot-free capture: Bot-free tools reduce meeting clutter but can hide capture from participants. Cerberus should pair no-bot operation with visible local state and explicit consent prompts.
- No durable meeting memory by default: Meeting tools sell searchable institutional memory. Cerberus currently remains stateless for screen Q&A; that is a privacy differentiator until opt-in local memory has deletion/export semantics.
- Mac-native trigger UX: Competitors optimize calendar/browser workflows. Cerberus can own AirPods, menu bar, local speech, and permission-aware screen questions.
- Screen context without meeting control: Meeting tools know calls and transcripts; Cerberus can answer visible-screen questions using OCR, UI geometry, barcodes, and optional local VLM without joining or operating meeting apps.
- Trust boundary clarity: Avoid CRM sync, MCP export, public share links, and team analytics in v1. These features create data spread faster than they create core assistant value.

## Recommendation

Cerberus should not become a general cloud meeting notetaker in v1. Keep the shipped product as stateless screen Q&A plus explicit local speech capture. A later meeting-notes direction is worth exploring only if it is:

- opt-in per session,
- visibly active,
- consent-gated,
- local-first,
- encrypted at rest,
- easy to delete/export,
- unavailable for interviews, exams, proctoring, or third-party monitoring without permission.

The best product overlap to copy is bot-free, low-friction capture and concise post-call summaries. The behavior to reject is silent capture, cloud memory by default, hidden coaching, and broad sharing/integration surfaces before the consent and storage model is mature.

## Sources Checked

- Granola homepage: https://www.granola.ai/
- Granola pricing: https://www.granola.ai/pricing
- Granola security: https://www.granola.ai/security
- Fathom homepage: https://www.fathom.ai/
- Fathom pricing: https://www.fathom.ai/pricing
- Fellow homepage: https://fellow.ai/
- Fellow pricing: https://fellow.ai/pricing
- Fellow Note Taker security/privacy: https://help.fellow.ai/en/articles/8137902-fellow-note-taker-security-privacy
- Read AI pricing: https://www.read.ai/plans-pricing
- Read AI account/privacy center: https://www.read.ai/account-and-privacy-center
- Fireflies homepage: https://fireflies.ai/
- Fireflies pricing: https://fireflies.ai/pricing
- Otter homepage: https://otter.ai/
- Otter pricing: https://otter.ai/pricing
- Otter privacy policy: https://otter.ai/privacy-policy
- Tactiq homepage: https://tactiq.io/
- Tactiq pricing: https://tactiq.io/buy
- Bluedot homepage: https://www.bluedothq.com/
- Bluedot pricing: https://www.bluedothq.com/pricing
- Jamie homepage: https://www.meetjamie.ai/en
- Jamie pricing: https://www.meetjamie.ai/pricing
