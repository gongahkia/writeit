# MCP

cerberus supports a minimal, default-off MCP stdio bridge through the `mcp.call` tool.

Config path:

```json
{
  "servers": [
    {
      "name": "local-demo",
      "executable": "node",
      "arguments": ["/absolute/path/to/server.js"],
      "workingDirectory": null
    }
  ]
}
```

Save this as `~/Library/Application Support/cerberus/mcp-servers.json`, then enable `MCP tool` in settings.

Current scope:

- stdio transport only
- `initialize`, `notifications/initialized`, `tools/list`, and `tools/call`
- each `mcp.call` is confirmation-gated
- tool output is treated as untrusted payload

Not implemented:

- Streamable HTTP
- resources
- prompts
- sampling
- elicitation
- dynamic FoundationModels native tool schemas
