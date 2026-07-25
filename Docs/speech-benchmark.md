# Speech Benchmark

Use the benchmark CLI to measure live SpeechAnalyzer transcription with the current macOS input device:

```sh
Scripts/benchmark_speech.sh --seconds 8 --expected "hey cerberus what text is on my screen"
```

Persist a JSON report:

```sh
Scripts/benchmark_speech.sh --seconds 8 --expected "hey cerberus what text is on my screen" --output .dist/validation/speech-quiet.json
```

For AirPods tests, select AirPods as the macOS input device before running the command. Repeat the same phrase in quiet, walking, and noisy-room conditions, then compare:

- first update latency
- finalization duration
- transcript text
- word error rate when `--expected` is provided
- JSON reports when `--output` is provided

The benchmark uses the same `Transcriber` path as the app. It requests microphone permission, records for the requested duration, finalizes SpeechAnalyzer input, and prints local metrics.

Official API surface used:

- `SpeechAnalyzer`
- `SpeechTranscriber`
- `AssetInventory`
- `AnalyzerInput`
