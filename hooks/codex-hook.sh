#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  printf 'codex-hook: usage: codex-hook.sh <hook-script> [args...]\n' >&2
  exit 2
fi

target="$1"
shift || true

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
adapter_root="$(cd "$script_dir/.." && pwd)"

case "$target" in
  /*) target_path="$target" ;;
  *)
    if [[ -n "${DEVKIT_ROOT:-}" && -x "$DEVKIT_ROOT/hooks/$target" ]]; then
      target_path="$DEVKIT_ROOT/hooks/$target"
    else
      target_path="$script_dir/$target"
    fi
    ;;
esac

if [[ ! -x "$target_path" ]]; then
  printf 'codex-hook: target is not executable: %s\n' "$target_path" >&2
  exit 2
fi

input="$(cat)"
hook_cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
if [[ -z "$hook_cwd" ]]; then
  hook_cwd="$(pwd)"
fi

export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${DEVKIT_ROOT:-$adapter_root}}"
export CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-$hook_cwd/.devkit}"

if [[ -z "$input" ]]; then
  printf '%s' "$input" | "$target_path" "$@"
  exit $?
fi

tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
hook_event_name="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null || true)"

if [[ "$tool_name" == "apply_patch" ]]; then
  input="$(printf '%s' "$input" | jq '
    def patch_path:
      (.tool_input.command // "")
      | split("\n")
      | map(capture("^\\*\\*\\* (Add|Update|Delete) File: (?<path>.+)$")? | .path)
      | map(select(. != null and . != ""))
      | .[0] // "";

    .tool_name = "Write"
    | .tool_input.file_path = patch_path
    | .tool_input.content = (.tool_input.command // "")
  ' 2>/dev/null || printf '%s' "$input")"
fi

output="$(printf '%s' "$input" | "$target_path" "$@")"
rc=$?

if [[ "$hook_event_name" == "Stop" ]]; then
  printf '%s' "$output" | jq -c '
    if (.decision // empty) == "block" then
      {
        hookSpecificOutput: {
          hookEventName: "Stop",
          decision: "block",
          reason: (.reason // "")
        }
      }
    else
      empty
    end
  ' 2>/dev/null || true
  exit "$rc"
fi

printf '%s' "$output"
exit "$rc"
