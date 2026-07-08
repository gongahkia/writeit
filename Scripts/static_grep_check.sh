#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/Scripts/open_source_check.sh" secrets

FORBIDDEN_SOURCE_PATTERNS=(
  "app"".""control"
  "browser"".""open"
  "browser"".""open_url"
  "browser"".""tabs"
  "calendar""."
  "contacts"".""search"
  "files.search"
  "finder"".""reveal"
  "mail"".""search"
  "mcp.call"
  "memory.read"
  "memory.write"
  "music""."
  "notes"".""search"
  "reminders""."
  "shell"".""run"
  "shortcuts"".""run"
  "web.search"
  "App""Control"
  "Browser""AppleScript"
  "Command""Allowlist"
  "Event""Kit"
  "FileSearch"
  "Finder""Reveal"
  "Mail""AppleScript"
  "MCP"
  "MCPOAuth"
  "Shell""Exec"
  "Shell""Tool"
  "Shortcuts""Run"
)

for pattern in "${FORBIDDEN_SOURCE_PATTERNS[@]}"; do
  if rg -n --fixed-strings "$pattern" "$ROOT_DIR/Sources" "$ROOT_DIR/Tests"; then
    echo "forbidden non-vision symbol found: $pattern" >&2
    exit 1
  fi
done
