#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
adapter_root="$(cd "$script_dir/.." && pwd)"

export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${DEVKIT_ROOT:-$adapter_root}}"

input="$(cat)"
hook_cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[[ -n "$hook_cwd" ]] || hook_cwd="$(pwd)"
export CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-$hook_cwd/.devkit}"

tmp_err="$(mktemp)"
trap 'rm -f "$tmp_err"' EXIT

set +e
printf '%s' "$input" | "$script_dir/codex-hook.sh" safety-check.sh >/dev/null 2>"$tmp_err"
rc=$?
set -e

if [[ "$rc" -eq 2 ]]; then
  reason="$(tr '\n' ' ' < "$tmp_err" | sed 's/[[:space:]]*$//')"
  [[ -n "$reason" ]] || reason="Blocked by devkit safety policy."
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      decision: {
        behavior: "deny",
        message: $reason
      }
    }
  }'
  exit 0
fi

exit 0
