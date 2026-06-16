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

Not implemented:

- adapter training
- LoRA dataset generation
- trainer orchestration
- adapter evaluation

I cannot verify a local FoundationModels training API in the installed SDK; the exposed API supports adapter loading, compilation, compatibility lookup, and cleanup.
