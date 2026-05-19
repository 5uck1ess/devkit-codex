# Changelog

## 1.0.0

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
- Slash command bridge now no-ops clearly when `DEVKIT_ROOT` is missing instead
  of silently searching the current working directory.
- Agent mapping now recognizes multiline `tools:` frontmatter.
- Smoke tests now cover skill dispatch, natural-language dispatch, apply-patch
  rewriting, Stop block rewriting, permission-deny behavior, and multiline
  agent tools.
- Release workflow now auto-bumps the patch version (matching core devkit)
  instead of failing when `manifest.json` is not ahead of the latest tag.
  Requires `secrets.VERSION_BUMP_KEY` to be configured as a deploy key with
  write access; without it, the bump-commit push step will fail.
- Release notes generation now tries both `## ${VERSION}` and `## v${VERSION}`
  headers in `CHANGELOG.md` (matching core devkit).
- Release workflow no longer corrupts the version when no git tags exist.
  Previously `git describe ... | sed ... || echo 0.0.0` ignored `git describe`'s
  failure because the `||` saw `sed`'s success on empty input, leaving
  `LATEST_TAG` empty and producing `version=..1` on the first release.
- Release `publish` job now checks out the repo so `gh release edit` can
  resolve the target repository from git context.
