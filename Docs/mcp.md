# MCP

cerberus supports a default-off MCP bridge through the MCP tool set.

Config path:

```json
{
  "servers": [
    {
      "name": "local-demo",
      "transport": "stdio",
      "executable": "node",
      "arguments": ["/absolute/path/to/server.js"],
      "workingDirectory": null
    },
    {
      "name": "remote-demo",
      "transport": "streamable_http",
      "endpointURL": "https://example.com/mcp",
      "headers": {
        "Authorization": "Bearer token"
      }
    }
  ]
}
```

Save this as `~/Library/Application Support/cerberus/mcp-servers.json`, then enable `MCP tool` in settings.

Current scope:

- stdio and Streamable HTTP transports
- `initialize`, `notifications/initialized`, `tools/list`, `tools/call`, `resources/list`, `resources/read`, `prompts/list`, and `prompts/get`
- each `mcp.call` is confirmation-gated
- tool/resource/prompt output is treated as untrusted payload

Not implemented:

- sampling
- elicitation
- dynamic FoundationModels native tool schemas
- OAuth discovery/PKCE
