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
- OAuth discovery, dynamic client registration, PKCE authorization URL generation, authorization-code token exchange, and refresh-token rotation for Streamable HTTP servers
- OAuth access tokens are stored in Keychain and attached as `Authorization: Bearer ...`; explicit config headers override Keychain tokens
- each `mcp.call` is confirmation-gated
- tool/resource/prompt output is treated as untrusted payload

Not implemented:

- sampling
- elicitation
- dynamic FoundationModels native tool schemas
- automatic localhost redirect capture
