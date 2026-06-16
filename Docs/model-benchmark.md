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

The native-tool mode uses the same read-only FoundationModels `Tool` session as the app, so local permissions and tool runtime costs affect the result. Use the synthetic mode for model-loop latency without Screen Recording, Calendar, Mail, or file-system side effects.

Official API surface used:

- `LanguageModelSession`
- `LanguageModelSession.respond`
- `Generable`
- `Tool`
