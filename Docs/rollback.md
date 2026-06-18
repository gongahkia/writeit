# Rollback

Use these steps to remove a local cerberus install and reset user state before reinstalling or testing a rollback build.

## Stop Running Processes

```sh
pkill -x cerberus || true
pkill -x ShellExecService || true
```

## Remove Launch Artifacts

```sh
rm -rf /Applications/cerberus.app
rm -rf "$HOME/Applications/cerberus.app"
rm -rf .dist/cerberus.app
rm -rf .dist/release/cerberus.zip .dist/release/cerberus.zip.sha256
rm -rf .dist/demo/cerberus-demo.mov
```

If the app was copied to another location, remove that `.app` bundle too.

## Remove App Data

```sh
rm -rf "$HOME/Library/Application Support/cerberus"
rm -rf "$HOME/Library/Caches/cerberus"
defaults delete dev.gongahkia.cerberus 2>/dev/null || true
```

This removes transcripts, memory, audit logs, MCP config, adapter config, wake samples, validation CSVs, cached screen snapshots, and persisted settings owned by the app.

## Remove Keychain Items

```sh
security delete-generic-password -s dev.gongahkia.cerberus -a transcript-encryption-key 2>/dev/null || true
security delete-generic-password -s dev.gongahkia.cerberus -a memory-encryption-key 2>/dev/null || true
security delete-generic-password -s dev.gongahkia.cerberus -a audit-signing-key 2>/dev/null || true
```

For MCP OAuth entries, delete accounts created from configured server names:

```sh
security delete-generic-password -s dev.gongahkia.cerberus -a "mcp.oauth.access.<serverName>" 2>/dev/null || true
security delete-generic-password -s dev.gongahkia.cerberus -a "mcp.oauth.client.<serverName>" 2>/dev/null || true
security delete-generic-password -s dev.gongahkia.cerberus -a "mcp.oauth.token.<serverName>" 2>/dev/null || true
security delete-generic-password -s dev.gongahkia.cerberus -a "mcp.oauth.flow.<serverName>.<state>" 2>/dev/null || true
```

If `mcp-servers.json` used a custom `accessTokenKeychainAccount`, delete that account name instead of `mcp.oauth.access.<serverName>`.

## Reset Permissions

```sh
tccutil reset All dev.gongahkia.cerberus
tccutil reset All dev.gongahkia.cerberus.ShellExecService
```

Open System Settings and remove any remaining Accessibility, Input Monitoring, Screen Recording, Automation, Microphone, Speech Recognition, Calendar, or Reminders grants if macOS still shows stale entries.

## Verify

```sh
test ! -d "$HOME/Library/Application Support/cerberus"
test ! -d "$HOME/Library/Caches/cerberus"
security find-generic-password -s dev.gongahkia.cerberus >/dev/null 2>&1 && exit 1 || true
```
