#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat || true)
[[ -z "$INPUT" ]] && exit 0

PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // .user_prompt // .input // empty' 2>/dev/null || true)
[[ -z "$PROMPT" ]] && exit 0

FIRST_LINE=$(printf '%s' "$PROMPT" | sed -n '1p')
DEVKIT_ROOT="${DEVKIT_ROOT:-$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)}"
[[ -n "$DEVKIT_ROOT" ]] || DEVKIT_ROOT="$(pwd)"

emit_context() {
  local context="$1"
  jq -n --arg context "$context" '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: $context
    }
  }'
}

trim_left() {
  local value="$1"
  printf '%s' "${value#"${value%%[![:space:]]*}"}"
}

valid_name() {
  local name="$1"
  [[ -n "$name" ]] || return 1
  case "$name" in
    *[!/A-Za-z0-9_-]* | *[./\\]*) return 1 ;;
  esac
  return 0
}

workflow_context() {
  local workflow="$1"
  local args="$2"
  cat <<CTX
Devkit workflow trigger detected: $workflow

Start the deterministic devkit workflow now:
1. Call the MCP tool devkit_start with workflow "$workflow" and input "$args".
2. Execute only the current step returned by the engine.
3. For command steps, do not run the command yourself; call devkit_advance so the engine executes it.
4. For prompt steps, do the requested work, report the step result as the devkit_advance output, then call devkit_advance.
5. Continue with devkit_advance until the workflow is complete. Do not skip, reorder, or merge steps.
CTX
}

skill_context() {
  local skill="$1"
  local args="$2"
  local path="skills/$skill/SKILL.md"
  cat <<CTX
Devkit skill trigger detected: $skill

Use the repository skill instructions at $path.
Read only that SKILL.md first, then follow its workflow for this request: $args
If the skill dispatches a devkit workflow, call devkit_start and then follow devkit_advance until complete.
If the skill is Claude-specific, use AGENTS.md or repo resources instead and report any unavailable Claude-only behavior.
CTX
}

dispatch_target() {
  local name="$1"
  local args="$2"

  valid_name "$name" || return 1
  [[ -n "$args" ]] || args="$PROMPT"

  if [[ -f "$DEVKIT_ROOT/workflows/$name.yml" || -f "$DEVKIT_ROOT/workflows/$name.yaml" ]]; then
    emit_context "$(workflow_context "$name" "$args")"
    return 0
  fi

  if [[ -f "$DEVKIT_ROOT/skills/$name/SKILL.md" ]]; then
    emit_context "$(skill_context "$name" "$args")"
    return 0
  fi

  return 1
}

case "$FIRST_LINE" in
  /devkit:*) RAW_NAME=${FIRST_LINE#/devkit:} ;;
  /*) RAW_NAME=${FIRST_LINE#/} ;;
  *) RAW_NAME="" ;;
esac

if [[ -n "$RAW_NAME" ]]; then
  NAME=${RAW_NAME%%[[:space:]]*}
  ARGS=${RAW_NAME#"$NAME"}
  ARGS=$(trim_left "$ARGS")
  dispatch_target "$NAME" "$ARGS" && exit 0
  exit 0
fi

PROMPT_LC=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')
case "$PROMPT_LC" in
  *"build a feature"* | *"new feature"* | *"add a feature"* | *"implement "*) dispatch_target "feature" "$PROMPT" && exit 0 ;;
  *"fix this bug"* | *"this is broken"* | *"bugfix"* | *"fix failing bug"*) dispatch_target "bugfix" "$PROMPT" && exit 0 ;;
  *"refactor this"* | *"clean up "*) dispatch_target "refactor" "$PROMPT" && exit 0 ;;
  *"deep research"* | *"validate this"*) dispatch_target "deep-research" "$PROMPT" && exit 0 ;;
  "research "* | *" research "*) dispatch_target "research" "$PROMPT" && exit 0 ;;
  *"make a pr"* | *"submit a pr"* | *"create a pull request"* | *"ship this"*) dispatch_target "pr-ready" "$PROMPT" && exit 0 ;;
  *"tri review"* | *"triple review"* | *"three-way code review"* | *"consensus code review"*) dispatch_target "tri-review" "$PROMPT" && exit 0 ;;
  *"tri debug"* | *"triple debug"*) dispatch_target "tri-debug" "$PROMPT" && exit 0 ;;
  *"tri security"* | *"triple security"* | *"security audit"*) dispatch_target "tri-security" "$PROMPT" && exit 0 ;;
  *"tri dispatch"* | *"send to three models"*) dispatch_target "tri-dispatch" "$PROMPT" && exit 0 ;;
  *"self-audit"*) dispatch_target "self-audit" "$PROMPT" && exit 0 ;;
  *"self-improve"* | *"keep fixing until"*) dispatch_target "self-improve" "$PROMPT" && exit 0 ;;
  *"self-lint"* | *"fix all lint"*) dispatch_target "self-lint" "$PROMPT" && exit 0 ;;
  *"self-migrate"* | *"migrate incrementally"*) dispatch_target "self-migrate" "$PROMPT" && exit 0 ;;
  *"self-perf"* | *"optimize performance"*) dispatch_target "self-perf" "$PROMPT" && exit 0 ;;
  *"self-test"* | *"fix failing tests"*) dispatch_target "self-test" "$PROMPT" && exit 0 ;;
  *"autoloop"* | *"run experiments overnight"*) dispatch_target "autoloop" "$PROMPT" && exit 0 ;;
  *"write tests for "*) dispatch_target "test-gen" "$PROMPT" && exit 0 ;;
  *"document this module"* | *"generate docs"* | *"write docs for "*) dispatch_target "doc-gen" "$PROMPT" && exit 0 ;;
  *"onboard to this codebase"* | *"help me understand this codebase"*) dispatch_target "onboard" "$PROMPT" && exit 0 ;;
  *"generate a changelog"* | *"release notes"*) dispatch_target "changelog" "$PROMPT" && exit 0 ;;
  *"create an adr"* | *"architecture decision record"*) dispatch_target "adr" "$PROMPT" && exit 0 ;;
  *"mega pr review"* | *"mega-pr"* | *"maximum coverage review"*) dispatch_target "mega-pr" "$PROMPT" && exit 0 ;;
  *"scrape this url"* | *"scrape "*) dispatch_target "scrape" "$PROMPT" && exit 0 ;;
  *"screenshot this"* | *"take a screenshot"*) dispatch_target "screenshot" "$PROMPT" && exit 0 ;;
  *"automate this browser"* | *"browser flow"*) dispatch_target "browser" "$PROMPT" && exit 0 ;;
  *"google workspace"* | *"gcli"*) dispatch_target "gcli" "$PROMPT" && exit 0 ;;
  *"devkit health"* | *"devkit status"* | *"is devkit working"* | *"what's installed"* | *"what devkit capabilities"*) dispatch_target "health" "$PROMPT" && exit 0 ;;
esac

exit 0
