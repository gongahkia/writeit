# Consent and Misuse Policy

Date: 2026-07-08

Cerberus is a local-first, observer-only macOS assistant. It can help the user understand their own screen, but it must not be used as a hidden assistant for exams, interviews, proctoring, meetings, or third-party conversations.

## Allowed Uses

- User-visible screen Q&A about the user's own Mac session.
- Accessibility-oriented reading of visible text, controls, charts, QR codes, and local UI state.
- Local meeting notes or summaries only when the user confirms that participants know AI audio/screen capture is active and the meeting's host, workplace, school, or platform policy allows it.
- Private rehearsal, mock interview practice, and study prep outside a live assessment, live interview, or proctored environment.

## Required Product Behavior

- Keep microphone and screen-capture state visible through the app surface.
- Keep activation explicit through the configured trigger, menu bar state, or wake phrase setting.
- Ask a concise consent question when a meeting or third-party conversation request does not state that participants know and permit AI capture.
- Refuse instead of asking a follow-up when the user asks for hidden, unauthorized, or deceptive assistance.
- Keep transcripts encrypted, audit-sensitive actions logged, and deletion paths documented.

## Refused Uses

- Exams, quizzes, homework, take-home assessments, coding assessments, oral exams, or proctored tests when the request is to get answers, bypass rules, or avoid detection.
- Live job interviews, hiring screens, technical interviews, sales role plays, or professional evaluations when the request is to produce hidden answers, coach the user without disclosure, or misrepresent the user's ability.
- Screen-share or proctoring bypass, including hiding the app, hiding from task switchers or process lists, defeating browser detection, avoiding monitoring warnings, or making assistance invisible to other participants.
- Recording, transcribing, summarizing, or monitoring meetings without participant knowledge and permission.
- Listening to, watching, or summarizing third-party conversations when the people involved have not consented.
- Reading, saving, or sharing passwords, secrets, private messages, sensitive personal data, confidential workplace data, or protected educational/medical/legal content without a clear legitimate local screen-reading purpose.

## Meeting Consent Rule

For meetings and third-party conversations, Cerberus should proceed only when the user states that participants know about the AI capture and the relevant policy permits it. If the user says "summarize this call" without consent context, Cerberus should ask whether all participants know and permit AI capture. If the user says "do it without them knowing", Cerberus should refuse.

## Implementation Hooks

- `SystemPrompt` must contain refusal rules for exams, interviews, proctoring, stealth bypass, recorded meetings, and non-consensual third-party conversations.
- `Docs/request-examples.md` must include refused examples for cheating, proctoring, surveillance, and stealth bypass.
- `Fixtures/Model/golden-requests.jsonl` must include prohibited request fixtures that expect `refuseUnsafeRequest`.
- Tests must keep the golden refusal IDs present and verify prompt wording for consent/misuse policy.

## Sources Checked

- Zoom AI Companion Meeting Summary support: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0058013
- FTC guidance on AI privacy and confidentiality commitments: https://www.ftc.gov/policy/advocacy-research/tech-at-ftc/2024/01/ai-companies-uphold-your-privacy-confidentiality-commitments
- UC Berkeley Zoom AI guidance: https://berkeley.service-now.com/kb_view.do?sysparm_article=KB0014837
