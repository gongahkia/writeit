# Local Vision Model Options

Status checked: 2026-07-08.

## Product Boundary

The Cluely niche is real-time audio plus screen context, but public positioning includes invisible/undetectable meeting assistance. Cerberus should stay transparent and observer-only: visible local menu bar app, no stealth overlay, no hidden screen-share bypass, no clicking/typing, no proctoring/interview cheating workflow.

## Candidate Models

- MiniCPM-V 4.6: best first local candidate for a Mac-local VLM path. Apache-2.0, image/video/text, explicitly positioned for on-device deployment including iOS.
- Qwen3-VL: strongest open-weight family to evaluate for quality. Apache-2.0 repo; 2B/4B/8B/32B and larger MoE releases exist. Likely heavier than MiniCPM for local Mac latency.
- Qwen2.5-VL 7B: stable Apache-2.0 fallback with strong OCR/document/layout reputation and broad runtime support.
- SmolVLM: Apache-2.0, small, fast, memory-efficient 2B-class option. Good fallback for low-memory machines, weaker than larger Qwen/InternVL families.
- Gemma 4: Apache-2.0, multimodal open-weights family with edge sizes. Evaluate once local runtime support is mature.
- InternVL3.5: MIT project with 1B/2B/4B/8B+ variants. Strong quality candidate; verify each model card license before bundling weights.
- Pixtral 12B: Apache-2.0 but deprecated by Mistral; keep only as a comparison baseline.
- Apple FastVLM: relevant architecture/runtime direction for MLX/Core ML integration; treat as research/demo path until a maintained production packaging path is selected.

## Integration Path

1. Keep current ScreenCaptureKit/Vision OCR tools as baseline.
2. Add optional local VLM provider behind a separate `screen.describe` read-only tool.
3. Use MLX first on Apple Silicon; consider llama.cpp/Ollama only as external user-installed providers.
4. Never send screenshots to network APIs in the default build.
5. Red-team for stealth/cheating misuse before adding always-on meeting/audio context.

## Current Config

`screen.describe` is disabled unless `~/Library/Application Support/cerberus/local-vlm.json` exists and validates. HTTP providers are localhost-only by default. If `allowNonLocalEndpoint` is true, screenshots and prompts are sent to that configured host; Cerberus does not download or install models automatically.

## MLX-VLM Setup

MLX-VLM is user-installed and user-updated. Create a separate Python environment, install `mlx-vlm`, verify the model from the shell, then point `local-vlm.json` at that interpreter or wrapper script. Upstream usage documents both `python -m mlx_vlm.generate ... --image <path>` and `python -m mlx_vlm.server`; see https://github.com/Blaizzy/mlx-vlm/blob/main/docs/usage.md.

Cerberus passes only the screenshot file path, prompt, model id, token limit, and timeout through configured argument placeholders. The subprocess provider requires `{image}` and `{prompt}` placeholders so screenshots are explicit inputs. Server mode must remain localhost unless `allowNonLocalEndpoint` is explicitly enabled.

## Ollama Setup

Ollama serves its local API at `http://localhost:11434/api` by default. Pull vision models yourself, then set `modelID` to the local model tag. Examples: `ollama pull llava` or `ollama pull minicpm-v`. Cerberus never runs `ollama pull`, never downloads models, and refuses remote Ollama endpoints unless `allowNonLocalEndpoint` is explicit. References: https://docs.ollama.com/api/introduction, https://ollama.com/library/llava, https://ollama.com/library/minicpm-v.

## llama.cpp Setup

llama.cpp support uses the isolated OpenAI-compatible chat completions path, not the Ollama request parser. Run `llama-server` yourself with a vision-capable GGUF model, required multimodal projector/options, and a supported chat template. Configure `provider` as `llama_cpp`; the default endpoint is `http://127.0.0.1:8080`. Runtime compatibility depends on the llama.cpp build, model, projector, and template. Cerberus does not build llama.cpp, download GGUF files, or open non-local endpoints by default. References: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md.

Ollama example:

```json
{
  "enabled": true,
  "provider": "ollama",
  "presetID": "minicpm-v-4.6",
  "modelID": "minicpm-v:latest",
  "endpointURLString": "http://127.0.0.1:11434",
  "arguments": [],
  "maxTokens": 256,
  "timeoutSeconds": 45,
  "allowNonLocalEndpoint": false
}
```

MLX-VLM subprocess example:

```json
{
  "enabled": true,
  "provider": "mlx_vlm",
  "presetID": "minicpm-v-4.6",
  "modelID": "openbmb/MiniCPM-V-4_6",
  "executablePath": "/usr/bin/env",
  "arguments": ["python3", "-m", "mlx_vlm.generate", "--model", "{model}", "--image", "{image}", "--prompt", "{prompt}", "--max-tokens", "{maxTokens}"],
  "maxTokens": 256,
  "timeoutSeconds": 45,
  "allowNonLocalEndpoint": false
}
```
