# devkit-codex

Codex adapter for [devkit](https://github.com/5uck1ess/devkit).

This repository contains the Codex-specific install script, lifecycle hook bridge,
slash-command prompt bridge, and agent mapping helper. The devkit workflow engine,
skills, workflows, and MCP server remain in the core `devkit` repository.

## Install

Clone both repositories locally, then install the adapter with the path to the
core devkit checkout:

```sh
git clone https://github.com/5uck1ess/devkit.git
git clone https://github.com/5uck1ess/devkit-codex.git
cd devkit-codex
./install.sh --devkit ../devkit
```

By default this writes:

- `~/.codex/config.toml`
- `~/.codex/hooks.json`

Use `--config` and `--hooks` to target alternate files, which is useful for
testing:

```sh
./install.sh --devkit ../devkit --config /tmp/codex-config.toml --hooks /tmp/codex-hooks.json
```

## Commands

```sh
./install.sh --check --devkit ../devkit
./install.sh --health --devkit ../devkit
./install.sh --uninstall
```

`--check` prints the planned install target without changing files.

`--health` verifies the adapter scripts, `jq`, the devkit executable, Codex MCP
config, and Codex hooks JSON.

`--uninstall` removes only devkit-codex-owned config and hooks. It leaves
non-devkit hooks files untouched.

## Behavior

- Registers the core devkit MCP server with Codex as `mcp_servers.devkit`.
- Enables Codex hooks in `config.toml`.
- Generates a devkit-owned `hooks.json` with Codex lifecycle hooks.
- Bridges `/feature`, `/bugfix`, `/tri-review`, `/health`, and other devkit
  workflow prompts into MCP-driven workflow instructions.
- Maps devkit agent definitions to Codex `explorer` or `worker` subagent
  guidance.

## Test

```sh
bash test/hooks_test.sh
bash -n install.sh
bash -n test/hooks_test.sh
```

The smoke test uses temporary fake devkit fixtures, so it does not require a
local devkit checkout.

## License

MIT. See [LICENSE](LICENSE).

## Release

Releases follow the same shape as the core devkit pipeline:

1. CI validates shell syntax, smoke tests, JSON, executable bits, and docs ignore
   rules.
2. Merged PRs to `main` trigger the release workflow.
3. The workflow reads `manifest.json`, creates a draft GitHub release, uploads a
   versioned source archive plus checksums, then publishes the release.

For the first public release, keep `manifest.json` at `0.0.1` and tag/release
`v0.0.1`.
