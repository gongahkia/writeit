# Model Benchmark

Use the benchmark CLI to measure Foundation Models latency for the app's planning and tool-output loop:

```sh
Scripts/benchmark_model.sh --request "what text is on my screen?" --iterations 5
```

Persist a JSON report:

```sh
Scripts/benchmark_model.sh --request "what text is on my screen?" --iterations 5 --output .dist/validation/model-loop.json
```

By default, the command measures:

- guided `AssistantPlan` generation
- synthetic tool-output summarization

It does not call live tools unless explicitly requested:

```sh
Scripts/benchmark_model.sh --native-read-only-tools --request "what text is on my screen?"
```

The native-tool mode uses the same read-only FoundationModels `Tool` session as the app, so local permissions and screen-tool runtime costs affect the result. Use the synthetic mode for model-loop latency without Screen Recording or live screen reads.

## 2026-07-08 M3 Baseline

Environment:

- MacBook Air Mac15,12, Apple M3, 8 cores, 16 GB memory
- macOS 26.5.1 25F80
- Xcode 26.6 17F113
- Swift 6.3.3, target `arm64-apple-macosx26.0`

Measured reports:

| Command | Plan median/p95 | Summarize median/p95 | Native answer median/p95 |
| --- | ---: | ---: | ---: |
| `Scripts/benchmark_model.sh --request "what text is on my screen?" --iterations 3 --output .dist/validation/model-loop.json` | 1.666s / 1.790s | 0.890s / 1.350s | n/a |
| `Scripts/benchmark_model.sh --native-read-only-tools --request "what text is on my screen?" --iterations 3 --output .dist/validation/model-native-tools.json` | 2.665s / 3.618s | 1.541s / 2.378s | 7.062s / 8.902s |

One-shot native read-only checks:

| Request | Tool | Plan | Summarize | Native answer |
| --- | --- | ---: | ---: | ---: |
| `capture what I am looking at` | `screen.snapshot` | 4.488s | 1.496s | 2.152s |
| `is there a QR code on screen?` | `screen.barcodes` | 3.136s | 1.009s | 2.756s |
| `what controls are visible in this app?` | `screen.ui_elements` | 4.961s | 2.162s | 9.333s |

[Inference] Accepted v1 gates for this hardware class:

- planning p95 <= 8.0s
- synthetic tool-output summarization p95 <= 5.0s
- `screen.ocr` native read-only answer p95 <= 25.0s
- one-shot `screen.snapshot`, `screen.barcodes`, and `screen.ui_elements` native answers <= 12.0s each

Optional `screen.describe` was not benchmarked in this run because `~/Library/Application Support/cerberus/local-vlm.json` was absent.

Plan drift fixtures:

```sh
Scripts/evaluate_model_golden_requests.sh
```

The script runs `Fixtures/Model/golden-requests.jsonl` through `cerberus-model-benchmark --golden-fixtures` and reports expected vs actual intent, tool name, and confirmation requirement for each request. Re-run it after SDK updates on target hardware.

2026-07-08 result on the M3 baseline machine: 31/31 fixtures passed, `golden.accuracy: 1.0000`.

Official API surface used:

- `LanguageModelSession`
- `LanguageModelSession.respond`
- `Generable`
- `Tool`
