#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ALLOW_DIRTY="${ALLOW_DIRTY:-0}"
REQUIRE_PUBLIC="${REQUIRE_PUBLIC:-1}"
FAILURES=0

usage() {
  print "usage: Scripts/open_source_check.sh [all|license|visibility|worktree|artifacts|secrets|github-security]"
  print ""
  print "env:"
  print "  ALLOW_DIRTY=1       allow uncommitted or untracked files"
  print "  REQUIRE_PUBLIC=0    do not fail while the GitHub repository is still private"
}

fail() {
  print -u2 "open-source check failed: $1"
  FAILURES=$((FAILURES + 1))
}

ok() {
  print "$1 ok"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    fail "$1 is not installed or not on PATH."
    return 1
  }
}

check_license() {
  if [[ -f "$ROOT_DIR/LICENSE" || -f "$ROOT_DIR/COPYING" ]]; then
    ok "license"
  else
    fail "add a LICENSE or COPYING file before publishing the repository."
  fi
}

check_visibility() {
  require_command gh || return
  local visibility
  visibility="$(cd "$ROOT_DIR" && gh repo view --json visibility -q .visibility 2>/dev/null)" || {
    fail "gh cannot read repository visibility."
    return
  }
  print "github visibility: $visibility"
  if [[ "$REQUIRE_PUBLIC" == "1" && "$visibility" != "PUBLIC" && "$visibility" != "public" ]]; then
    fail "repository visibility is $visibility, not PUBLIC."
  else
    ok "visibility"
  fi
}

check_worktree() {
  local status_text
  status_text="$(cd "$ROOT_DIR" && git status --porcelain)"
  if [[ -n "$status_text" && "$ALLOW_DIRTY" != "1" ]]; then
    fail "working tree has uncommitted or untracked files. Set ALLOW_DIRTY=1 for prep checks."
    print -u2 "$status_text"
  else
    ok "worktree"
  fi
}

check_artifacts() {
  local tracked_path
  local bad=()
  while IFS= read -r tracked_path; do
    case "$tracked_path" in
      .build/*|.dist/*|DerivedData/*|*.app/*|*.xpc/*|*.xcresult|*.mov|*.mp4|*.m4v|*.zip|*.tar|*.tar.gz)
        bad+=("$tracked_path")
        ;;
    esac
  done < <(cd "$ROOT_DIR" && git ls-files)

  if (( ${#bad[@]} > 0 )); then
    fail "tracked build/release artifacts found:"
    print -u2 -- ${(F)bad}
  else
    ok "artifacts"
  fi
}

check_secrets() {
  local private_key_matches
  private_key_matches="$(cd "$ROOT_DIR" && git grep -I -n -E -- '-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----' . ':!Package.resolved' 2>/dev/null || true)"

  local secret_regex
  secret_regex="([Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd])[[:space:]]*[:=][[:space:]]*['\"][^'\"]{16,}['\"]"
  local secret_matches
  secret_matches="$(cd "$ROOT_DIR" && git grep -I -n -E -- "$secret_regex" . ':!Package.resolved' 2>/dev/null || true)"

  if [[ -n "$private_key_matches" || -n "$secret_matches" ]]; then
    fail "possible tracked secrets found:"
    [[ -z "$private_key_matches" ]] || print -u2 "$private_key_matches"
    [[ -z "$secret_matches" ]] || print -u2 "$secret_matches"
  else
    ok "secrets"
  fi
}

check_github_security() {
  require_command gh || return

  local visibility
  visibility="$(cd "$ROOT_DIR" && gh repo view --json visibility -q .visibility 2>/dev/null)" || {
    fail "gh cannot read repository visibility for GitHub security checks."
    return
  }
  local visibility_lower="${visibility:l}"

  local vulnerability_status
  vulnerability_status="$(cd "$ROOT_DIR" && gh api -i repos/:owner/:repo/vulnerability-alerts -X GET 2>/dev/null | awk 'index($0, "HTTP/") == 1 { status = $2 } END { print status }')"
  case "$vulnerability_status" in
    204)
      ok "dependabot-alerts"
      ;;
    404)
      fail "Dependabot alerts are not enabled."
      ;;
    *)
      fail "could not verify Dependabot alerts status."
      ;;
  esac

  local security_updates
  security_updates="$(cd "$ROOT_DIR" && gh api repos/:owner/:repo/automated-security-fixes --jq '[.enabled, .paused] | @tsv' 2>/dev/null || true)"
  if [[ "$security_updates" == $'true\tfalse' ]]; then
    ok "dependabot-security-updates"
  else
    fail "Dependabot security updates are not enabled and unpaused."
  fi

  local code_scanning_error
  if code_scanning_error="$(cd "$ROOT_DIR" && gh api repos/:owner/:repo/code-scanning/alerts --paginate --jq 'length' 2>&1 >/dev/null)"; then
    ok "code-scanning"
  elif [[ "$REQUIRE_PUBLIC" == "0" && "$visibility_lower" != "public" ]]; then
    print "code-scanning deferred until repository is public or GitHub Code Security is enabled"
  else
    fail "code scanning is not enabled: $code_scanning_error"
  fi

  local security_statuses
  security_statuses="$(cd "$ROOT_DIR" && gh api repos/:owner/:repo --jq '[.security_and_analysis.secret_scanning.status, .security_and_analysis.secret_scanning_push_protection.status] | @tsv' 2>/dev/null || true)"
  if [[ -z "${security_statuses//[$'\t ']/}" ]]; then
    if [[ "$REQUIRE_PUBLIC" == "0" && "$visibility_lower" != "public" ]]; then
      print "secret-scanning and push-protection deferred until repository is public or GitHub Secret Protection is enabled"
    else
      fail "GitHub API did not return security_and_analysis for secret scanning and push protection."
    fi
    return
  fi

  local secret_scanning_status="${security_statuses%%$'\t'*}"
  local push_protection_status="${security_statuses#*$'\t'}"
  if [[ "$secret_scanning_status" == "enabled" ]]; then
    ok "secret-scanning"
  else
    fail "secret scanning is $secret_scanning_status, not enabled."
  fi
  if [[ "$push_protection_status" == "enabled" ]]; then
    ok "push-protection"
  else
    fail "push protection is $push_protection_status, not enabled."
  fi
}

run_all() {
  check_license
  check_visibility
  check_worktree
  check_artifacts
  check_secrets
  check_github_security
}

case "${1:-all}" in
  -h|--help)
    usage
    ;;
  all)
    run_all
    ;;
  license)
    check_license
    ;;
  visibility)
    check_visibility
    ;;
  worktree)
    check_worktree
    ;;
  artifacts)
    check_artifacts
    ;;
  secrets)
    check_secrets
    ;;
  github-security)
    check_github_security
    ;;
  *)
    usage
    exit 64
    ;;
esac

if (( FAILURES > 0 )); then
  exit 65
fi
