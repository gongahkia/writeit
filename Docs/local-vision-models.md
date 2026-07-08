# Local Vision Model Options

Status checked: 2026-07-08.

## Product Boundary

The Cluely niche is real-time audio plus screen context, but public positioning includes invisible/undetectable meeting assistance. Cerberus should stay transparent and observer-only: visible local menu bar app, no stealth overlay, no hidden screen-share bypass, no clicking/typing, no proctoring/interview cheating workflow.

## Candidate Models

- MiniCPM-V 4.6: best first local candidate for a Mac-local VLM path. Source checked 2026-07-08: Apache-2.0 on Hugging Face, image/video/text, edge/mobile oriented, and OpenBMB reports vLLM, SGLang, llama.cpp, and Ollama support.
- Qwen3-VL: strongest open-weight family to evaluate for quality. Source checked 2026-07-08: Apache-2.0 GitHub repo with 2B, 4B, 8B, 30B-A3B, 32B, and 235B-A22B releases. GUI-agent capabilities must stay disabled; passive VQA only.
- Qwen2.5-VL 7B: stable fallback. Source checked 2026-07-08: Apache-2.0 7B Instruct checkpoint, 3B edge variant documented, strong OCR/document/layout/chart/UI screenshot use cases.
- SmolVLM: source checked 2026-07-08. Apache-2.0, small, fast, memory-efficient 2B-class option. Low-resource fallback only; weaker quality than MiniCPM, Qwen, and InternVL.
- Gemma 4: source checked 2026-07-08. Apache-2.0 for `google/gemma-4-E2B-it`; Google MLX docs verify a local MLX-VLM path for `mlx-community/gemma-4-e2b-it-4bit`. Keep as a fallback until benchmarked locally.
- InternVL3.5: source checked 2026-07-08. Apache-2.0 for selected 1B/2B/4B/8B checkpoints. Strong quality candidate; config-only fallback until local benchmarks pass.
- Pixtral 12B: Apache-2.0 but deprecated by Mistral; keep only as a comparison baseline.
- Apple FastVLM: source checked 2026-07-08. Apple-native MLX/Core ML research/demo path with Apple AMLR research-only weights. Keep experimental and never default.

## Integration Path

1. Keep current ScreenCaptureKit/Vision OCR tools as baseline.
2. Add optional local VLM provider behind a separate `screen.describe` read-only tool.
3. Use MLX first on Apple Silicon; consider llama.cpp/Ollama only as external user-installed providers.
4. Never send screenshots to network APIs in the default build.
5. Red-team for stealth/cheating misuse before adding always-on meeting/audio context.

## Current Config

`screen.describe` is disabled unless `~/Library/Application Support/cerberus/local-vlm.json` exists and validates. HTTP providers are localhost-only by default. If `allowNonLocalEndpoint` is true, screenshots and prompts are sent to that configured host; Cerberus does not download or install models automatically.

## MiniCPM-V 4.6 Preset

Preset id: `minicpm-v-4.6`. Default model id for OpenAI-compatible routes: `openbmb/MiniCPM-V-4.6`. This is config-only; no model weights, GGUF files, or runtime packages are bundled. Source/license checked 2026-07-08: https://huggingface.co/openbmb/MiniCPM-V-4.6 and https://github.com/OpenBMB/MiniCPM-V. Ollama packaging checked 2026-07-08: https://ollama.com/openbmb/minicpm-v4.6.

Runtime variants to evaluate:
- MLX-VLM: use the generic subprocess path with `python -m mlx_vlm.generate`; validate the checkpoint locally before marking pass.
- Ollama: use `openbmb/minicpm-v4.6`; keep endpoint on `127.0.0.1:11434`.
- llama.cpp: use a vision-capable GGUF plus required multimodal projector/options; keep endpoint on `127.0.0.1:8080`.
- vLLM/SGLang: use `openai_compatible`; non-local GPU servers require `allowNonLocalEndpoint: true` and send screenshots off-Mac.

Benchmark checklist: UI screenshot, dense text, chart, code editor, QR/barcode, low-light image. Template: `Fixtures/VLM/benchmark-template.json`.

## Qwen3-VL Passive Preset

Preset id: `qwen3-vl`. Source/license checked 2026-07-08: https://github.com/QwenLM/Qwen3-VL and https://huggingface.co/collections/Qwen/qwen3-vl. Supported release sizes observed in upstream notes: 2B, 4B, 8B, 30B-A3B, 32B, and 235B-A22B.

Qwen3-VL upstream documents visual-agent capabilities for GUI operation. Cerberus must not expose those behaviors. Use `screen.describe` only for passive screen VQA, OCR-style explanation, visible state summaries, and uncertainty reporting. Do not use it for clicking, typing, app control, navigation, web operation, mobile/desktop agent tasks, or action plans. `ScreenDescribeTool` wraps every local VLM prompt with observe-only instructions before calling the provider.

## Qwen2.5-VL Fallback Preset

Preset id: `qwen2.5-vl`. Source/license checked 2026-07-08: https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct and https://ollama.com/library/qwen2.5vl. This is a config-only fallback; no weights are bundled. Use the 7B Instruct checkpoint first for OCR/document/layout evaluation; the 3B variant is the smaller practical edge candidate and must be verified separately.

Expected strengths: dense OCR, scanned documents, forms, charts, icon/layout understanding, and UI screenshots. Qwen2.5-VL also documents visual-agent capability, so it remains behind the same passive `screen.describe` prompt wrapper as Qwen3-VL.

Runtime support checked: vLLM/SGLang examples on the Hugging Face model card, Ollama `qwen2.5vl`, and llama.cpp-compatible quantizations linked from the model card. Keep local endpoints on localhost unless `allowNonLocalEndpoint` is explicit.

Benchmark comparison: run `Fixtures/VLM/benchmark-template.json` across `minicpm-v-4.6`, `qwen3-vl`, and `qwen2.5-vl`; compare OCR exactness, layout fidelity, chart reading, UI element grounding, latency, and refusal/observe-only behavior.

## SmolVLM Fallback Preset

Preset id: `smolvlm`. Source/license checked 2026-07-08: https://huggingface.co/blog/smolvlm and https://github.com/huggingface/smollm. This is a config-only fallback; no weights are bundled. Use it only when the machine cannot run MiniCPM-V 4.6, Qwen3-VL, Qwen2.5-VL, or InternVL at acceptable latency.

Positioning: small-memory, low-cost passive VQA. It is not the best-quality default. Expect weaker dense OCR, chart reasoning, document layout, and UI grounding than MiniCPM/Qwen/InternVL. Preset metadata recommends `maxTokens` 128 and timeout 30 seconds to keep low-resource runs bounded.

## Gemma 4 Fallback Preset

Preset id: `gemma-4`. Selected checkpoint: `google/gemma-4-E2B-it`. Source/license checked 2026-07-08: https://huggingface.co/google/gemma-4-E2B-it and https://ai.google.dev/gemma/docs/core/model_card_4. The official model card reports Apache-2.0. No weights, MLX conversions, LiteRT packages, or runtime packages are bundled.

Runtime path checked 2026-07-08: Google MLX docs list `pip install mlx mlx-lm mlx-vlm`, `mlx_vlm.generate --model mlx-community/gemma-4-e2b-it-4bit --prompt "Describe this image." --image <path_to_image>`, and `mlx_vlm.server --model mlx-community/gemma-4-e2b-it-4bit`, with an OpenAI-compatible localhost endpoint at `http://localhost:8080/v1`: https://ai.google.dev/gemma/docs/integrations/mlx. The downstream MLX conversion card is https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit; verify conversion metadata and redistribution terms before redistributing converted weights.

## InternVL3.5 Fallback Preset

Preset id: `internvl3.5`. Selected checkpoints: `OpenGVLab/InternVL3_5-1B`, `OpenGVLab/InternVL3_5-2B`, `OpenGVLab/InternVL3_5-4B`, and `OpenGVLab/InternVL3_5-8B`. Source/license checked 2026-07-08: https://huggingface.co/OpenGVLab/InternVL3_5-1B, https://huggingface.co/OpenGVLab/InternVL3_5-2B, https://huggingface.co/OpenGVLab/InternVL3_5-4B, and https://huggingface.co/OpenGVLab/InternVL3_5-8B. Each selected card reports Apache-2.0. No weights, quantizations, or runtime packages are bundled. The preset is disabled by default because `screen.describe` only loads after `local-vlm.json` exists and validates.

Runtime paths checked 2026-07-08: the selected HF cards list Transformers, vLLM, SGLang, Docker Model Runner, and quantization browse routes. The shared model card also documents LMDeploy with `lmdeploy serve api_server OpenGVLab/InternVL3_5-8B --server-port 23333 --tp 1 --backend pytorch`, exposing an OpenAI-compatible local service. References: https://github.com/OpenGVLab/InternVL and https://internvl.github.io/blog/2025-08-26-InternVL-3.5/.

Hardware expectations: upstream states models up to 30B can deploy on one A100 GPU, with 38B requiring two A100 GPUs and the 235B language model requiring eight A100 GPUs. The selected 1B/2B/4B/8B set shares a 0.3B vision encoder and totals about 1.1B, 2.3B, 4.7B, and 8.5B parameters. [Inference] Start Mac-local validation with 1B or 2B, and treat 4B/8B as GPU-backed or quantized-runtime targets until benchmark data exists. GUI and embodied-agent abilities must remain disabled behind passive `screen.describe`.

## Apple FastVLM Experimental Preset

Preset id: `fastvlm`. Selected demo checkpoints: `apple/FastVLM-0.5B`, `apple/FastVLM-1.5B`, and `apple/FastVLM-7B`. Source/license checked 2026-07-08: https://huggingface.co/apple/FastVLM-0.5B, https://huggingface.co/apple/FastVLM-1.5B, https://huggingface.co/apple/FastVLM-7B, and https://huggingface.co/apple/FastVLM-0.5B/blob/main/LICENSE. Hugging Face reports `apple-amlr`; the license text limits weights and derivatives to research purposes. No weights, exported models, Core ML packages, or runtime packages are bundled.

Runtime commands checked 2026-07-08:
- Official repo setup and PyTorch path: `conda create -n fastvlm python=3.10`, `pip install -e .`, `bash get_models.sh`, then `python predict.py --model-path /path/to/checkpoint-dir --image-file /path/to/image.png --prompt "Describe the image."`: https://github.com/apple/ml-fastvlm.
- Apple Silicon export path: `python export_vision_encoder.py --model-path /path/to/fastvlm-checkpoint`, patch `mlx-vlm` at commit `1884b551bc741f26b2d54d68fa89d4e934b9a3de`, `python -m mlx_vlm.convert --hf-path /path/to/fastvlm-checkpoint --mlx-path /path/to/exported-fastvlm --only-llm`, then `python -m mlx_vlm.generate --model /path/to/exported-fastvlm --image /path/to/image.png --prompt "Describe the image." --max-tokens 256 --temp 0.0`: https://github.com/apple/ml-fastvlm/tree/main/model_export.
- Demo app path: `app/get_pretrained_mlx_model.sh --model 0.5b --dest app/FastVLM/model`, then build/run the Xcode app. The app README states iOS 18.2+ and macOS 15.2+ support: https://github.com/apple/ml-fastvlm/tree/main/app.

FastVLM remains research/demo only. Do not make it the default provider. If `presetID` is `fastvlm`, the settings status line includes `(experimental)`.

## MLX-VLM Setup

MLX-VLM is user-installed and user-updated. Create a separate Python environment, install `mlx-vlm`, verify the model from the shell, then point `local-vlm.json` at that interpreter or wrapper script. Upstream usage documents both `python -m mlx_vlm.generate ... --image <path>` and `python -m mlx_vlm.server`; see https://github.com/Blaizzy/mlx-vlm/blob/main/docs/usage.md.

Cerberus passes only the screenshot file path, prompt, model id, token limit, and timeout through configured argument placeholders. The subprocess provider requires `{image}` and `{prompt}` placeholders so screenshots are explicit inputs. Server mode must remain localhost unless `allowNonLocalEndpoint` is explicitly enabled.

## Ollama Setup

Ollama serves its local API at `http://localhost:11434/api` by default. Pull vision models yourself, then set `modelID` to the local model tag. Examples: `ollama pull llava` or `ollama pull minicpm-v`. Cerberus never runs `ollama pull`, never downloads models, and refuses remote Ollama endpoints unless `allowNonLocalEndpoint` is explicit. References: https://docs.ollama.com/api/introduction, https://ollama.com/library/llava, https://ollama.com/library/minicpm-v.

## llama.cpp Setup

llama.cpp support uses the isolated OpenAI-compatible chat completions path, not the Ollama request parser. Run `llama-server` yourself with a vision-capable GGUF model, required multimodal projector/options, and a supported chat template. Configure `provider` as `llama_cpp`; the default endpoint is `http://127.0.0.1:8080`. Runtime compatibility depends on the llama.cpp build, model, projector, and template. Cerberus does not build llama.cpp, download GGUF files, or open non-local endpoints by default. References: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md.

## vLLM and SGLang Setup

vLLM and SGLang are advanced OpenAI-compatible endpoint options for users who operate their own GPU server. Configure `provider` as `openai_compatible` and keep `endpointURLString` on localhost unless you explicitly accept screenshot egress. Setting `allowNonLocalEndpoint` to `true` means screenshots and prompts leave the Mac for that endpoint. Cerberus does not provision servers, manage API keys, download models, or verify LAN security. Runtime compatibility depends on the selected VLM, chat template, server version, and OpenAI vision request support. References: https://docs.vllm.ai/en/stable/serving/online_serving/, https://docs.sglang.ai/.

Ollama example:

```json
{
  "enabled": true,
  "provider": "ollama",
  "presetID": "minicpm-v-4.6",
  "modelID": "openbmb/minicpm-v4.6",
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
  "modelID": "openbmb/MiniCPM-V-4.6",
  "executablePath": "/usr/bin/env",
  "arguments": ["python3", "-m", "mlx_vlm.generate", "--model", "{model}", "--image", "{image}", "--prompt", "{prompt}", "--max-tokens", "{maxTokens}"],
  "maxTokens": 256,
  "timeoutSeconds": 45,
  "allowNonLocalEndpoint": false
}
```
