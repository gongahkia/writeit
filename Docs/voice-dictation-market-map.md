# Voice Dictation Market Map

Date: 2026-07-08

Scope: Voice-first macOS assistants and dictation tools adjacent to Cerberus. This comparison uses public vendor claims and docs checked on the date above; it is not a hands-on latency, word-error-rate, or noisy-AirPods benchmark.

## Summary

Voice-first tools cluster into three product shapes:

- Polished cloud dictation: Wispr Flow and Aqua optimize low-friction "speak anywhere" UX, auto-edits, command/edit modes, and cross-device settings, but route transcription through cloud services.
- Local-first Mac dictation: Superwhisper, MacWhisper, VoiceInk, and Voibe emphasize on-device transcription, push-to-talk shortcuts, custom modes, and privacy.
- Command-control systems: Apple Voice Control and Talon focus on explicit command grammars, mode switching, screen labels, and hands-free navigation.

[Inference] Cerberus should copy interaction mechanics, not cloud dictation architecture. The right bar for AirPods operation is fast explicit capture, audible state, clean cancel/undo, visible transcript review, command/dictation mode separation, and local-first transcription.

## Comparison

| Product | Latency signal | Offline support | Correction UX | Command mode | Pricing observed | Privacy posture | Mac integration |
| --- | --- | --- | --- | --- | --- | --- | --- |
| [Superwhisper](https://superwhisper.com/) | Vendor claims up to 5x faster writing; hold-to-record/release-to-paste app flow | Offline and cloud speech recognition; Intel Macs work best with cloud, offline runs best on Apple Silicon | Custom modes, prompts, presets, history search, bring-your-own API keys | Custom AI modes and mode switching; not a full OS command grammar | Free tier; Pro $8.49/mo, yearly/lifetime options shown; Enterprise custom | Privacy policy says audio/transcripts are processed locally by default, not collected, not retained on servers, and not used for training | macOS, Windows, iOS; works in any app |
| [Wispr Flow](https://wisprflow.ai/) | Vendor claims 4x faster than typing, auto-edits, and lowest-latency cloud server probing | No local offline path; official data controls say transcription always occurs on the cloud | Auto-edits, personal dictionary, snippets, local edit detection, delete account/data path | Pro includes Command Mode for editing | Basic free with weekly word caps; Pro $15/user/mo monthly or $12/user/mo annually; Enterprise custom | Privacy Mode disables training/evaluation use; Private Cloud Sync controls retention; zero retention requires Privacy Mode on and Cloud Sync off | Mac, Windows, iPhone, Android; account/settings sync |
| [Aqua Voice](https://aquavoice.com/) | Streaming mode, real-time refinement, "without delay"; iOS launch highlights ultra low latency | No offline mode found in checked official pages; privacy page describes server-side transcript handling | Custom dictionary, writing style rules, secure transcript history, iOS Voice Edit Mode | Voice Edit Mode on iOS; custom prompting/writing rules; no full OS command grammar found | 1,000 free words; Pro $8/mo billed annually; student discount; Enterprise/custom implied | Privacy Mode off/on changes transcript collection; with Privacy Mode disabled transcripts may be stored; SOC 2 Type II claim | macOS Apple Silicon/Intel, Windows, iPhone |
| [MacWhisper](https://www.macwhisper.com/) | Vendor positions real-time dictation plus local file/meeting transcription; no benchmark checked | Local models, offline processing, and Ollama/LM Studio support | Transcript editor/search/export, auto cleanup, grammar improvement, AI dictation prompts, app-specific prompts | Dictation feature into any text field; not a broad OS command layer | Free forever; Pro EUR64 one-time license with lifetime updates | Local models for sensitive files; offline processing without data leaving the Mac; BYO API keys optional for AI services | Mac-native app, direct-download dictation, app-audio and meeting recording, CLI/workflow hooks |
| [VoiceInk](https://tryvoiceink.com/) | Vendor claims almost-instant local transcription and 5x faster writing | 100% offline local transcription on Apple Silicon; optional cloud enhancement sends text only if enabled | Personal dictionary, smart replacements, enhancement prompts, app/website modes, context awareness | AI Assistant prompt can answer/summarize/give commands; modes auto-switch by app/site | One-time lifetime licenses: $25 one Mac, $39 two Macs, $49 three Macs | Open source; voice transcription stays local; optional cloud enhancement uses transcribed text, not voice | macOS 14.4+ Apple Silicon; global shortcuts and push-to-talk |
| [Voibe](https://www.getvoibe.com/) | Vendor claims 5x faster voice typing and lightning-fast local dictation | Fully offline, on-device; Apple Silicon only | Developer Mode, Memory, custom vocabulary, smart punctuation | Developer Mode; not a full OS command grammar found | $7.50/mo, $59/year, or $149 lifetime; team plans | Audio transcribed in device RAM, never uploaded/stored/used for training per FAQ | macOS 13+ Apple Silicon; works in every app |
| [Apple Dictation and Voice Control](https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac) | Native OS flow; no vendor latency benchmark checked | Keyboard settings disclose whether general Dictation is on-device or sent to Siri servers | Ambiguous text underlines, alternatives, typed/dictated correction, punctuation, new-line commands | Voice Control has Dictation/Command/Spelling modes, screen labels/numbers, "stop listening/start listening" | Bundled with macOS | User choice for Improve Siri and Dictation audio sharing; delete Siri/Dictation history under 6 months | Deepest macOS integration, microphone source selection, VoiceOver support, headphones tip |
| [Talon](https://talonvoice.com/) | Built for hands-free control, coding, noises, and eye tracking; no vendor latency benchmark checked | Comes with a free speech recognition engine; community docs describe local Conformer install | Scriptable Python commands and user file sets; no AI cleanup by default | Core strength: command/dictation/sleep modes and custom grammars | Public app royalty-free under EULA; Patreon supports early access/support | No official privacy page found in checked sources; local engine path reduces cloud dependency | macOS, Windows, Linux/X11; deep automation if user accepts setup burden |

## AirPods UX Features Cerberus Should Adopt

- Push-to-talk first: Use an explicit AirPods stem press or menu bar shortcut for capture. Avoid always-listening dictation as the default.
- Audible states: Play short start, stop, cancel, and error earcons through AirPods so the user knows when audio is being captured.
- Visible states: Mirror the audio state in the menu bar: idle, listening, transcribing, asking, speaking, failed.
- Dictation vs command modes: Separate "ask Cerberus" from "edit/cancel/retry". Apple Voice Control and Talon show why mode separation matters.
- Cancel and undo: Support "cancel that", "try again", "stop listening", and stem-press cancel before any model request is sent.
- Transcript preview: Show the captured text before sending when confidence is low, when the prompt mentions third parties, or when consent context is missing.
- Personal vocabulary: Add a local dictionary for app names, contact names, jargon, project names, and "Cerberus" so AirPods mic errors are less costly.
- Context-aware prompts with boundaries: Use visible app/screen context to format the query, but keep screen text local and consent-gated.
- Offline default: Keep SpeechAnalyzer/local transcription as the first path. Do not add a silent cloud fallback.
- Bounded history: Keep short local transcript history only when the user enables it; otherwise discard audio/transcript after the turn.
- Noisy route checks: Benchmark AirPods mic in quiet, keyboard, commute, and meeting-room conditions before treating AirPods as a reliable trigger source.
- Recovery path: If AirPods disconnect or mic confidence drops, fall back to Mac mic only with visible status and user confirmation.

## Recommendation

Cerberus should not compete as a general dictation replacement in v1. It should adopt the dictation tools' best interaction primitives for a narrower assistant loop:

1. press or gesture,
2. hear capture start,
3. speak one screen-aware request,
4. see transcript if needed,
5. answer locally,
6. speak response through AirPods,
7. discard turn data unless audit/transcript storage is explicitly enabled.

[Inference] The best v1 benchmark is not "writes 5x faster". It is "a user wearing AirPods can ask a short screen question, recover from a bad transcript, and know exactly when Cerberus is listening".

## Sources Checked

- Superwhisper homepage/pricing: https://superwhisper.com/
- Superwhisper privacy: https://superwhisper.com/privacy
- Superwhisper App Store: https://apps.apple.com/us/app/superwhisper-ai-dictation/id6471464415
- Wispr Flow homepage: https://wisprflow.ai/
- Wispr Flow pricing: https://wisprflow.ai/pricing
- Wispr Flow data controls: https://wisprflow.ai/data-controls
- Wispr Flow plans: https://docs.wisprflow.ai/articles/9559327591-flow-plans-and-what-s-included
- Wispr Flow account management: https://docs.wisprflow.ai/articles/7339517111-manage-your-flow-account
- Wispr Flow connection issues: https://docs.wisprflow.ai/articles/3834764683-why-vpns-or-security-tools-can-block-wispr-flow
- Aqua Voice homepage: https://aquavoice.com/
- Aqua Voice FAQ: https://aquavoice.com/info/faq
- Aqua Voice privacy: https://aquavoice.com/info/privacy
- Aqua Voice iOS launch: https://aquavoice.com/blog/aqua-voice-for-ios
- MacWhisper homepage/pricing: https://www.macwhisper.com/
- MacWhisper dictation docs: https://docs.macwhisper.com/article/14-how-to-use-the-dictation-feature
- VoiceInk homepage/pricing/privacy FAQ: https://tryvoiceink.com/
- VoiceInk GitHub: https://github.com/Beingpax/VoiceInk
- Voibe homepage: https://www.getvoibe.com/
- Voibe pricing: https://www.getvoibe.com/pricing/
- Apple Dictation: https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac
- Apple Voice Control commands: https://support.apple.com/guide/mac-help/use-voice-control-commands-mh40719/mac
- Talon homepage: https://talonvoice.com/
- Talon docs: https://talonvoice.com/docs/
- Talon EULA: https://talonvoice.com/EULA.txt
