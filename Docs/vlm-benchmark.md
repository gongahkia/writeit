# VLM Benchmark

Use the benchmark CLI to measure local VLM screenshot+prompt latency and capture JSON reports:

```bash
Scripts/benchmark_vlm.sh --provider ollama --model-id minicpm-v --generated-fixture
```

Reports default to `.dist/validation/vlm-<timestamp>.json`. Each report includes provider, model id, preset id, prompt, input mode, image fixture, image path, latency, success/failure, response, error, max tokens, and timeout. The generated fixture is a redacted PNG with no screen content. Use `--live-screen --scope main_display` only after granting Screen Recording.

## MLX-VLM

```bash
Scripts/benchmark_vlm.sh \
  --provider mlx_vlm \
  --preset-id minicpm-v-4.6 \
  --model-id openbmb/MiniCPM-V-4.6 \
  --executable /usr/bin/env \
  --arg python3 --arg -m --arg mlx_vlm.generate \
  --arg --model --arg '{model}' \
  --arg --image --arg '{image}' \
  --arg --prompt --arg '{prompt}' \
  --arg --max-tokens --arg '{maxTokens}' \
  --generated-fixture \
  --output .dist/validation/vlm-mlx.json
```

## Ollama

```bash
ollama pull minicpm-v
Scripts/benchmark_vlm.sh \
  --provider ollama \
  --preset-id minicpm-v-4.6 \
  --model-id minicpm-v \
  --endpoint http://127.0.0.1:11434 \
  --generated-fixture \
  --output .dist/validation/vlm-ollama.json
```

## llama.cpp

```bash
Scripts/benchmark_vlm.sh \
  --provider llama_cpp \
  --preset-id minicpm-v-4.6 \
  --model-id openbmb/MiniCPM-V-4.6-GGUF \
  --endpoint http://127.0.0.1:8080 \
  --generated-fixture \
  --output .dist/validation/vlm-llama-cpp.json
```

## OpenAI-Compatible

```bash
Scripts/benchmark_vlm.sh \
  --provider openai_compatible \
  --preset-id qwen2.5-vl \
  --model-id Qwen/Qwen2.5-VL-7B-Instruct \
  --endpoint http://127.0.0.1:8000 \
  --live-screen --scope main_display \
  --output .dist/validation/vlm-openai-compatible.json
```

Non-local endpoints require `--allow-non-local-endpoint`; that sends screenshots and prompts to that host.
