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

Not implemented:

- adapter training
- trainer orchestration
- adapter evaluation

Apple's adapter training toolkit is a separate Python workflow. It requires prompt/response JSONL data, train/eval splits, Python 3.11+, toolkit downloads tied to a specific system-model version, and separate adapters for model-version updates. I cannot verify a local FoundationModels Swift training API in the installed SDK; the exposed Swift API supports adapter loading, compilation, compatibility lookup, and cleanup.
