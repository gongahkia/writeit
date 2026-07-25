# Demo Script

Use this outline when recording `.dist/demo/cerberus-demo.mov`.

1. Trigger: open the menu bar panel, start listening with Control-Option-Space or `Listen`, and show the red microphone-active menu bar state.
2. Speech: say "hey cerberus what is on my screen" or type the request if the recording environment is noisy, then let the silence timeout move the app into reasoning.
3. Read-only tool: run a read-only request such as "what text is on my screen?" or "what controls are visible in this app?" and show the spoken/text response.
4. Refusal: ask "pause Music" or "search Mail for receipts", then show that this build can only observe and answer.
5. Audit review: open the Audit section, refresh entries, then ask "what did cerberus just do?" to show the latest audited action summary.

For a deterministic local video without live permissions, use:

```sh
DEMO_CAPTURE_MODE=rendered DEMO_SECONDS=36 Scripts/record_demo.sh
```
