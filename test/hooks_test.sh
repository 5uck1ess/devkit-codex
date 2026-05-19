#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
TMP_DIRS=()

cleanup() {
  for dir in "${TMP_DIRS[@]}"; do
    rm -rf "$dir"
  done
}
trap cleanup EXIT

pass(){ echo "PASS: $1"; PASS=$((PASS+1)); }
fail(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

fake_devkit=$(mktemp -d)
TMP_DIRS+=("$fake_devkit")
mkdir -p "$fake_devkit/bin" "$fake_devkit/hooks" "$fake_devkit/workflows" "$fake_devkit/agents" "$fake_devkit/skills"
cat > "$fake_devkit/bin/devkit" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$fake_devkit/bin/devkit"
touch "$fake_devkit/workflows/feature.yml"
touch "$fake_devkit/workflows/tri-security.yml"
mkdir -p "$fake_devkit/skills/audit"
cat > "$fake_devkit/skills/audit/SKILL.md" <<'MD'
---
name: audit
---

Audit skill fixture.
MD
cat > "$fake_devkit/agents/researcher.md" <<'MD'
---
tools: Read, Grep, Glob
---

Researcher agent fixture.
MD
cat > "$fake_devkit/agents/builder.md" <<'MD'
---
tools:
  - Read
  - Edit
  - Write
---

Builder agent fixture.
MD
cat > "$fake_devkit/hooks/echo-input.sh" <<'SH'
#!/usr/bin/env bash
cat
SH
cat > "$fake_devkit/hooks/block-stop.sh" <<'SH'
#!/usr/bin/env bash
printf '{"decision":"block","reason":"workflow incomplete"}\n'
SH
cat > "$fake_devkit/hooks/safety-check.sh" <<'SH'
#!/usr/bin/env bash
input=$(cat)
if printf '%s' "$input" | jq -e '.tool_input.command | contains("rm -rf")' >/dev/null 2>&1; then
  printf 'dangerous command denied\n' >&2
  exit 2
fi
exit 0
SH
chmod +x "$fake_devkit/hooks/echo-input.sh" "$fake_devkit/hooks/block-stop.sh" "$fake_devkit/hooks/safety-check.sh"
DEVKIT_ROOT="${DEVKIT_ROOT:-$fake_devkit}"

out=$(jq -n --arg cwd "$DEVKIT_ROOT" '{hook_event_name:"UserPromptSubmit",cwd:$cwd,prompt:"/feature tiny no-op"}' | DEVKIT_ROOT="$DEVKIT_ROOT" bash "$ROOT/hooks/codex-slash-commands.sh" 2>/dev/null || true)
if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("workflow \"feature\"")' >/dev/null; then
  pass "slash bridge injects workflow"
else
  fail "slash bridge missing workflow"
fi

skill_out=$(jq -n --arg cwd "$DEVKIT_ROOT" '{hook_event_name:"UserPromptSubmit",cwd:$cwd,prompt:"/audit now"}' | DEVKIT_ROOT="$DEVKIT_ROOT" bash "$ROOT/hooks/codex-slash-commands.sh" 2>/dev/null || true)
if printf '%s' "$skill_out" | jq -e '.hookSpecificOutput.additionalContext | contains("skill trigger detected: audit")' >/dev/null; then
  pass "slash bridge injects skill"
else
  fail "slash bridge missing skill"
fi

nl_out=$(jq -n --arg cwd "$DEVKIT_ROOT" '{hook_event_name:"UserPromptSubmit",cwd:$cwd,prompt:"please run a security audit"}' | DEVKIT_ROOT="$DEVKIT_ROOT" bash "$ROOT/hooks/codex-slash-commands.sh" 2>/dev/null || true)
if printf '%s' "$nl_out" | jq -e '.hookSpecificOutput.additionalContext | contains("workflow \"tri-security\"")' >/dev/null; then
  pass "slash bridge covers natural-language trigger"
else
  fail "slash bridge natural-language trigger failed"
fi

unset_out=$(jq -n '{hook_event_name:"UserPromptSubmit",cwd:"/tmp",prompt:"/feature tiny no-op"}' | env -u DEVKIT_ROOT bash "$ROOT/hooks/codex-slash-commands.sh" 2>/dev/null || true)
if [[ -z "$unset_out" ]]; then
  pass "slash bridge no-ops without DEVKIT_ROOT"
else
  fail "slash bridge emitted output without DEVKIT_ROOT"
fi

agent=$(DEVKIT_ROOT="$DEVKIT_ROOT" bash "$ROOT/codex/agent-prompt.sh" researcher 2>/dev/null || true)
if printf '%s' "$agent" | grep -q 'Recommended Codex subagent type: explorer'; then
  pass "agent mapper works"
else
  fail "agent mapper failed"
fi

worker_agent=$(DEVKIT_ROOT="$DEVKIT_ROOT" bash "$ROOT/codex/agent-prompt.sh" builder 2>/dev/null || true)
if printf '%s' "$worker_agent" | grep -q 'Recommended Codex subagent type: worker'; then
  pass "agent mapper handles multiline tools"
else
  fail "agent mapper multiline tools failed"
fi

bad=$(bash "$ROOT/codex/agent-prompt.sh" '../bad' >/dev/null 2>&1; echo $?)
if [[ "$bad" -eq 2 ]]; then
  pass "agent mapper rejects invalid name"
else
  fail "agent mapper invalid-name exit $bad"
fi

patch_input=$(jq -n --arg command '*** Begin Patch
*** Update File: src/main.go
@@
-old
+new
*** End Patch
' '{tool_name:"apply_patch",tool_input:{command:$command}}')
patch_out=$(printf '%s' "$patch_input" | DEVKIT_ROOT="$DEVKIT_ROOT" bash "$ROOT/hooks/codex-hook.sh" echo-input.sh)
if printf '%s' "$patch_out" | jq -e '.tool_name == "Write" and .tool_input.file_path == "src/main.go" and (.tool_input.content | contains("*** Update File: src/main.go"))' >/dev/null; then
  pass "codex hook rewrites apply_patch input"
else
  fail "codex hook apply_patch rewrite failed"
fi

stop_out=$(jq -n '{hook_event_name:"Stop"}' | DEVKIT_ROOT="$DEVKIT_ROOT" bash "$ROOT/hooks/codex-hook.sh" block-stop.sh)
if printf '%s' "$stop_out" | jq -e '.hookSpecificOutput.hookEventName == "Stop" and .hookSpecificOutput.decision == "block" and .hookSpecificOutput.reason == "workflow incomplete"' >/dev/null; then
  pass "codex hook rewrites Stop block output"
else
  fail "codex hook Stop block rewrite failed"
fi

perm_out=$(jq -n '{cwd:"/tmp",tool_name:"Bash",tool_input:{command:"rm -rf /tmp/nope"}}' | DEVKIT_ROOT="$DEVKIT_ROOT" bash "$ROOT/hooks/codex-permission-guard.sh")
if printf '%s' "$perm_out" | jq -e '.hookSpecificOutput.hookEventName == "PermissionRequest" and .hookSpecificOutput.decision.behavior == "deny"' >/dev/null; then
  pass "permission guard denies unsafe command"
else
  fail "permission guard deny path failed"
fi

install_tmp=$(mktemp -d)
TMP_DIRS+=("$install_tmp")
config_path="$install_tmp/config.toml"
hooks_path="$install_tmp/hooks.json"

bash "$ROOT/install.sh" --devkit "$fake_devkit" --config "$config_path" --hooks "$hooks_path" >/dev/null
if jq . "$hooks_path" >/dev/null; then
  pass "install writes valid hooks JSON"
else
  fail "install hooks JSON invalid"
fi
if grep -q '^\[mcp_servers\.devkit\]$' "$config_path"; then
  pass "install writes devkit MCP config"
else
  fail "install missing MCP config"
fi
if grep -q '^hooks = true$' "$config_path"; then
  pass "install enables Codex hooks feature"
else
  fail "install missing hooks feature"
fi
if grep -q "^env = { CLAUDE_PLUGIN_ROOT = \"$fake_devkit\" }$" "$config_path"; then
  pass "install sets devkit MCP CLAUDE_PLUGIN_ROOT"
else
  fail "install missing devkit MCP CLAUDE_PLUGIN_ROOT"
fi

health_out=$(bash "$ROOT/install.sh" --devkit "$fake_devkit" --config "$config_path" --hooks "$hooks_path" --health 2>&1)
health_rc=$?
if [[ "$health_rc" -eq 0 ]] && printf '%s' "$health_out" | grep -q 'ok: Codex hooks are devkit-owned and valid JSON'; then
  pass "install health reports healthy adapter"
else
  fail "install health failed rc=$health_rc output=$health_out"
fi

check_out=$(bash "$ROOT/install.sh" --devkit "$fake_devkit" --config "$config_path" --hooks "$hooks_path" --check)
if printf '%s' "$check_out" | grep -q 'Would install devkit-codex'; then
  pass "install check is dry-run"
else
  fail "install check output unexpected: $check_out"
fi

cat >> "$config_path" <<'TOML'

[mcp_servers.other]
command = "other"
TOML
bash "$ROOT/install.sh" --devkit "$fake_devkit" --config "$config_path" --hooks "$hooks_path" >/dev/null
mcp_count=$(grep -c '^\[mcp_servers\.devkit\]$' "$config_path")
if [[ "$mcp_count" -eq 1 ]] && grep -q '^\[mcp_servers\.other\]$' "$config_path"; then
  pass "reinstall replaces only devkit MCP block"
else
  fail "reinstall config merge failed"
fi

bash "$ROOT/install.sh" --config "$config_path" --hooks "$hooks_path" --uninstall >/dev/null
if ! grep -q '^\[mcp_servers\.devkit\]$' "$config_path" && [[ ! -e "$hooks_path" ]] && [[ -e "$hooks_path.bak" ]]; then
  pass "uninstall removes devkit-owned config and hooks"
else
  fail "uninstall did not remove devkit-owned entries"
fi

printf '{"description":"custom hooks","hooks":{}}\n' > "$hooks_path"
bash "$ROOT/install.sh" --config "$config_path" --hooks "$hooks_path" --uninstall >/dev/null
if [[ -e "$hooks_path" ]] && grep -q 'custom hooks' "$hooks_path"; then
  pass "uninstall preserves non-devkit hooks"
else
  fail "uninstall changed non-devkit hooks"
fi

force_hooks="$install_tmp/force-hooks.json"
printf '{"description":"custom hooks","hooks":{}}\n' > "$force_hooks"
bash "$ROOT/install.sh" --devkit "$fake_devkit" --config "$config_path" --hooks "$force_hooks" --force >/dev/null
if [[ -e "$force_hooks.bak" ]] && grep -q 'custom hooks' "$force_hooks.bak" && jq . "$force_hooks" >/dev/null; then
  pass "force install backs up foreign hooks once"
else
  fail "force install backup failed"
fi
printf '{"description":"new custom hooks","hooks":{}}\n' > "$force_hooks"
bash "$ROOT/install.sh" --devkit "$fake_devkit" --config "$config_path" --hooks "$force_hooks" --force >/dev/null
if grep -q 'custom hooks' "$force_hooks.bak" && ! grep -q 'new custom hooks' "$force_hooks.bak"; then
  pass "force install preserves first hooks backup"
else
  fail "force install clobbered hooks backup"
fi

if bash "$ROOT/install.sh" --devkit >/dev/null 2>&1; then
  fail "install rejects missing --devkit value"
else
  pass "install rejects missing --devkit value"
fi

echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
