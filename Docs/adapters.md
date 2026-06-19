# FoundationModels Adapters

cerberus can load a prebuilt FoundationModels adapter at startup.

Config path:

```json
{
  "name": "com.example.adapter"
}
```

or:

```json
{
  "filePath": "/absolute/path/to/adapter"
}
```

Save this as `~/Library/Application Support/cerberus/foundation-model-adapter.json`.

Current scope:

- loads one prebuilt adapter
- calls `compile()` before switching sessions to the adapter-backed model
- reuses the same tool registry and safety gates
- exports encrypted transcript records into basic Foundation Models adapter-training JSONL prompt/response pairs

Export a local dataset:

```sh
Scripts/export_adapter_dataset.sh
```

The exporter writes:

- `~/Library/Application Support/cerberus/adapter-dataset/train.jsonl`
- `~/Library/Application Support/cerberus/adapter-dataset/eval.jsonl`

Each JSONL line is the basic Apple toolkit schema:

```json
[{"role":"user","content":"PROMPT"},{"role":"assistant","content":"RESPONSE"}]
```

Optional arguments:

```sh
Scripts/export_adapter_dataset.sh /tmp/cerberus-adapter-data --eval-fraction 0.2 --limit 1000
```

The exporter writes `stats.json` and redacts email addresses, bearer tokens, long hex tokens, and `/Users/...` home paths by default. Use `--no-redact` only for a private local review pass where exact values are needed.

## Human Review Workflow

Use this before training:

1. Export with default redaction:

   ```sh
   Scripts/export_adapter_dataset.sh /tmp/cerberus-adapter-data --eval-fraction 0.2 --limit 1000
   ```

2. Review `stats.json` for unexpected task categories, tool names, and response-length outliers.
3. Read `train.jsonl` and `eval.jsonl` locally. Do not upload them to external review tools.
4. Delete rows that contain private data, unsafe tool behavior, failed tool calls, hallucinated actions, or low-quality responses.
5. Save curated files as `train.reviewed.jsonl` and `eval.reviewed.jsonl`.
6. Run eval on the curated split:

   ```sh
   Scripts/evaluate_adapter_dataset.sh /tmp/cerberus-adapter-data/eval.reviewed.jsonl --limit 20
   ```

7. Train only from reviewed files by copying them over `train.jsonl` and `eval.jsonl` in the private training directory used for `Scripts/train_adapter.sh`.

Keep rejected rows out of the training directory. If exact private values are required for a local-only investigation, keep that copy outside `.dist/`, outside git, and delete it after review.

Evaluate an eval split with the default model:

```sh
Scripts/evaluate_adapter_dataset.sh /tmp/cerberus-adapter-data/eval.jsonl --limit 20
```

Evaluate with a configured prebuilt adapter:

```sh
Scripts/evaluate_adapter_dataset.sh /tmp/cerberus-adapter-data/eval.jsonl --adapter-config ~/Library/Application\ Support/cerberus/foundation-model-adapter.json
```

The evaluator runs each prompt through Foundation Models and reports exact normalized response-match accuracy. Use it as a smoke metric; adapter quality still needs task-specific human or automated review.

## Latest Local Preflight

2026-06-19 local export:

- output: `.dist/validation/adapter-data`
- train: 107 rows
- eval: 27 rows
- redaction: enabled
- private-data scan: 0 email, home path, bearer token, or long-hex matches in train/eval
- base eval smoke: `Scripts/evaluate_adapter_dataset.sh .dist/validation/adapter-data/eval.jsonl --limit 5` returned 0/5 exact matches and 0.0 average token F1
- curation: all 107 train rows and 27 eval rows rejected as synthetic/stub-quality data; empty reviewed splits were written to `.dist/validation/adapter-data/train.reviewed.jsonl` and `.dist/validation/adapter-data/eval.reviewed.jsonl`

The exported split is not training-ready. Real transcript history is still required before adapter training.

Train with Apple's adapter training toolkit:

```sh
ADAPTER_TOOLKIT_DIR=/path/to/foundation-models-adapter-toolkit \
DATA_DIR=/tmp/cerberus-adapter-data \
Scripts/train_adapter.sh
```

The wrapper expects the toolkit's documented Python modules, reads `train.jsonl` and `eval.jsonl`, runs `examples.train_adapter`, and exports an `.fmadapter` with `export.export_fmadapter`.

Optional environment:

```sh
ADAPTER_NAME=cerberus_adapter
EPOCHS=5
LEARNING_RATE=1e-3
BATCH_SIZE=4
TRAIN_DRAFT=0
EXPORT_ADAPTER=1
CHECKPOINT_DIR=.dist/adapter-training/checkpoints
EXPORT_DIR=.dist/adapter-training/exports
```

Not implemented:

- adapter training

Apple's adapter training toolkit is a separate Python workflow. It requires prompt/response JSONL data, train/eval splits, Python 3.11+, toolkit downloads tied to a specific system-model version, and separate adapters for model-version updates. `Scripts/train_adapter.sh` orchestrates the toolkit after you download it; it cannot train without the toolkit assets. I cannot verify a local FoundationModels Swift training API in the installed SDK; the exposed Swift API supports adapter loading, compilation, compatibility lookup, and cleanup.

Apple's adapter training page was re-checked on 2026-06-19 at `https://developer.apple.com/apple-intelligence/foundation-models-adapter/`. Apple documents version 26.0.0 as the last toolkit release, compatible with macOS/iOS/iPadOS/visionOS 26 and not 27 or later. Downloading any toolkit version requires Apple Developer Program membership and accepting the toolkit terms. Local training also requires Apple silicon with at least 32 GB memory or a Linux GPU machine, Python 3.11+, quality prompt/response data, and separate adapters for every system model version.
