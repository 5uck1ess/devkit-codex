# Changelog

## 0.0.1

Initial public release of the Codex adapter for devkit.

### Added

- Codex installer that registers the core devkit MCP server and hook config.
- Codex lifecycle hook bridge for devkit safety, audit, workflow, permission,
  post-tool, and stop guards.
- Slash-command prompt bridge for devkit workflows and skills.
- Agent mapping helper for translating devkit agent definitions into Codex
  subagent guidance.
- Installer `--check`, `--health`, `--uninstall`, and `--force` behavior.
- Self-contained smoke tests for hook JSON, slash bridge, agent mapping,
  installer health, reinstall idempotency, and uninstall behavior.
- GitHub Actions CI and release workflows for public releases.
- MIT license and manifest metadata for public distribution.

### Fixed

- Install now prechecks `jq` before mutating Codex config.
- Install and uninstall now write Codex config/hooks atomically.
- Backups preserve the first pre-adapter state instead of clobbering `.bak`
  on repeated installs.
- CI now runs on both Ubuntu and macOS.
