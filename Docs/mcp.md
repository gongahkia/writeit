# MCP

cerberus supports a default-off MCP bridge through the `mcp.call` tool.

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
- `initialize`, `notifications/initialized`, `tools/list`, `tools/call`, `resources/list`, and `resources/read`
- each `mcp.call` is confirmation-gated
- tool/resource output is treated as untrusted payload

Not implemented:

- prompts
- sampling
- elicitation
- dynamic FoundationModels native tool schemas
- OAuth discovery/PKCE
