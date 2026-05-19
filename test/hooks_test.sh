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
cat > "$fake_devkit/agents/researcher.md" <<'MD'
---
tools: Read, Grep, Glob
---

Researcher agent fixture.
MD
DEVKIT_ROOT="${DEVKIT_ROOT:-$fake_devkit}"

if jq . "$ROOT/codex/hooks.template.json" >/dev/null; then
  pass "hooks template valid JSON"
else
  fail "hooks template invalid JSON"
fi

out=$(jq -n --arg cwd "$DEVKIT_ROOT" '{hook_event_name:"UserPromptSubmit",cwd:$cwd,prompt:"/feature tiny no-op"}' | DEVKIT_ROOT="$DEVKIT_ROOT" bash "$ROOT/hooks/codex-slash-commands.sh" 2>/dev/null || true)
if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("workflow \"feature\"")' >/dev/null; then
  pass "slash bridge injects workflow"
else
  fail "slash bridge missing workflow"
fi

agent=$(cd "$DEVKIT_ROOT" && DEVKIT_ROOT="$DEVKIT_ROOT" bash "$ROOT/codex/agent-prompt.sh" researcher 2>/dev/null || true)
if printf '%s' "$agent" | grep -q 'Recommended Codex subagent type: explorer'; then
  pass "agent mapper works"
else
  fail "agent mapper failed"
fi

bad=$(bash "$ROOT/codex/agent-prompt.sh" '../bad' >/dev/null 2>&1; echo $?)
if [[ "$bad" -eq 2 ]]; then
  pass "agent mapper rejects invalid name"
else
  fail "agent mapper invalid-name exit $bad"
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

echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
