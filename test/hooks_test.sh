#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVKIT_ROOT="${DEVKIT_ROOT:-/Users/anotherlostsoul/Documents/LocalDev/devkit}"
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

jq . "$ROOT/codex/hooks.template.json" >/dev/null && pass "hooks template valid JSON" || fail "hooks template invalid JSON"

out=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","cwd":"'$DEVKIT_ROOT'","prompt":"/feature tiny no-op"}' | DEVKIT_ROOT="$DEVKIT_ROOT" bash "$ROOT/hooks/codex-slash-commands.sh" 2>/dev/null || true)
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("workflow \"feature\"")' >/dev/null && pass "slash bridge injects workflow" || fail "slash bridge missing workflow"

agent=$(cd "$DEVKIT_ROOT" && DEVKIT_ROOT="$DEVKIT_ROOT" bash "$ROOT/codex/agent-prompt.sh" researcher 2>/dev/null || true)
printf '%s' "$agent" | grep -q 'Recommended Codex subagent type: explorer' && pass "agent mapper works" || fail "agent mapper failed"

bad=$(bash "$ROOT/codex/agent-prompt.sh" '../bad' >/dev/null 2>&1; echo $?)
[[ "$bad" -eq 2 ]] && pass "agent mapper rejects invalid name" || fail "agent mapper invalid-name exit $bad"

fake_devkit=$(mktemp -d)
TMP_DIRS+=("$fake_devkit")
mkdir -p "$fake_devkit/bin" "$fake_devkit/hooks" "$fake_devkit/workflows" "$fake_devkit/agents" "$fake_devkit/skills"
cat > "$fake_devkit/bin/devkit" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$fake_devkit/bin/devkit"

install_tmp=$(mktemp -d)
TMP_DIRS+=("$install_tmp")
config_path="$install_tmp/config.toml"
hooks_path="$install_tmp/hooks.json"

bash "$ROOT/install.sh" --devkit "$fake_devkit" --config "$config_path" --hooks "$hooks_path" >/dev/null
jq . "$hooks_path" >/dev/null && pass "install writes valid hooks JSON" || fail "install hooks JSON invalid"
grep -q '^\[mcp_servers\.devkit\]$' "$config_path" && pass "install writes devkit MCP config" || fail "install missing MCP config"
grep -q '^hooks = true$' "$config_path" && pass "install enables Codex hooks feature" || fail "install missing hooks feature"

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
