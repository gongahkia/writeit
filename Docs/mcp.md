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
      "protectedResourceMetadataURL": "https://example.com/.well-known/oauth-protected-resource",
      "oauthClientID": "optional-client-id",
      "oauthRedirectURI": "http://127.0.0.1:8765/callback",
      "oauthScopes": ["read"],
      "accessTokenKeychainAccount": "mcp.oauth.access.remote-demo",
      "nativeReadOnlyTools": ["search"],
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
- OAuth discovery, dynamic client registration, PKCE authorization URL generation, authorization-code token exchange, one-shot localhost callback capture, and refresh-token rotation for Streamable HTTP servers
- OAuth access tokens are stored in Keychain and attached as `Authorization: Bearer ...`; explicit config headers override Keychain tokens
- stdio server requests for `sampling/createMessage` and `elicitation/create` are routed through the app's review UI when MCP tools are enabled
- Streamable HTTP POST responses with SSE server requests are handled the same way, with JSON-RPC responses posted back to the server
- Streamable HTTP GET listeners start for configured HTTP servers when MCP tools are enabled; servers that return 405 are treated as not exposing the listener
- GET listeners track SSE event IDs and reconnect with `Last-Event-ID`
- sampling requests require prompt approval and response approval before returning content to the MCP server
- elicitation requests use generated controls for flat primitive schemas, with JSON fallback plus accept, decline, and cancel actions
- accepted elicitation content is validated against the MCP flat primitive schema subset before returning to the server
- each `mcp.call` is confirmation-gated
- configured `nativeReadOnlyTools` are exposed as FoundationModels native tools through dynamic schemas for flat primitive JSON-object inputs
- tool/resource/prompt output is treated as untrusted payload

Only put trusted read-only tool names in `nativeReadOnlyTools`; this path is not used for mutating tools because native tool calls do not go through the app-owned confirmation gate.
