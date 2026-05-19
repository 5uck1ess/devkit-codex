#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s <agent-name>\n' "${0##*/}" >&2
  printf 'available agents:\n' >&2
  find "$DEVKIT_ROOT/agents" -maxdepth 1 -type f -name '*.md' -print 2>/dev/null \
    | sed 's|.*/||; s|\.md$||' | sort | sed 's/^/  - /' >&2
}

DEVKIT_ROOT="${DEVKIT_ROOT:-}"
if [[ -z "$DEVKIT_ROOT" ]]; then
  here="$(pwd)"
  while [[ "$here" != / ]]; do
    if [[ -d "$here/agents" && -d "$here/workflows" ]]; then
      DEVKIT_ROOT="$here"
      break
    fi
    here="$(dirname "$here")"
  done
fi
[[ -n "$DEVKIT_ROOT" ]] || DEVKIT_ROOT="$(pwd)"

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

AGENT="$1"
case "$AGENT" in
  *[!/A-Za-z0-9_-]* | *[./\\]* | "")
    printf 'invalid agent name: %s\n' "$AGENT" >&2
    exit 2
    ;;
esac

AGENT_FILE="$DEVKIT_ROOT/agents/$AGENT.md"
if [[ ! -f "$AGENT_FILE" ]]; then
  printf 'unknown agent: %s\n' "$AGENT" >&2
  usage
  exit 2
fi

tools_block=$(awk '
  /^tools:/ {
    in_tools=1
    print
    next
  }
  in_tools && /^[^[:space:]-]/ {
    exit
  }
  in_tools {
    print
  }
' "$AGENT_FILE" 2>/dev/null || true)
if printf '%s' "$tools_block" | grep -qE '\b(Edit|Write)\b'; then
  codex_type="worker"
  ownership="Assign a bounded write scope before spawning. The worker must not edit outside that ownership without asking."
else
  codex_type="explorer"
  ownership="Assign a bounded read-only question or review scope. The explorer must not edit files."
fi

cat <<OUT
Codex devkit agent mapper

Agent: $AGENT
Definition: agents/$AGENT.md
Recommended Codex subagent type: $codex_type
Required final output shape:

Spawn guidance:
- Use spawn_agent with agent_type "$codex_type".
- Tell the subagent it is not alone in the codebase and must not revert edits made by others.
- $ownership
- Include the role definition below in the subagent prompt.
- Require final output in this exact shape:

files_read:
- <path or none>

files_changed:
- <path or none>

verification:
- <command/result or not run: reason>

result:
<concise outcome, findings, or implementation summary>

risks:
- <remaining risk, assumption, or none>

- For read-only agents, files_changed must be "none".
- For write-capable agents, require exact changed paths and the test/lint command result.

Role definition:
$(cat "$AGENT_FILE")
OUT
