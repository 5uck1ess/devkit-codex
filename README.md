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

After installing, start a new Codex session and run:

```text
/hooks
```

Codex requires first-run review for new non-managed command hooks before they
can run. Review the devkit-codex hook commands, confirm that the paths point to
your local `devkit` and `devkit-codex` checkouts, then trust them.

For less fragile hook commands, install with an absolute devkit path:

```sh
./install.sh --devkit "$(cd ../devkit && pwd)"
```

Start Codex from a git repository when testing workflows. The core devkit MCP
server expects to start inside a project repo; a plain directory will make MCP
startup fail before `devkit_start` and `devkit_advance` are exposed.

Codex CLI handles `/` commands itself, so unknown slash commands such as
`/feature` may be rejected before hooks can inspect them. To run a devkit
workflow in Codex, use the text trigger form:

```text
devkit feature: add a tiny no-op test file
```

```text
devkit workflow tri-security: audit this repository
```

Natural-language prompts can also dispatch common workflows:

```text
please run a security audit
```

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
- Bridges devkit workflow prompts such as feature requests, bugfixes,
  tri-review, health checks, and security audits into MCP-driven workflow
  instructions.
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
