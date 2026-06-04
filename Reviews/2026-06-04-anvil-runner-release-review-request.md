# AnvilRunner Release Readiness Review Request

## Intent

Review `swiftanvil-anvil-runner` as a standalone SwiftAnvil library and CLI for managing small fleets of
self-hosted GitHub Actions runners on macOS.

The intended product direction is:

- provide safe, local-first runner installation and lifecycle management
- make cleanup operations constrained, inspectable, and testable
- avoid credential leakage in documented workflows
- support organization-level release standards: PR workflow, CI, local enforcement, sibling-host review,
  licensing, agent instructions, and roadmap

This review is for the plan and implementation direction, not only code style. Challenge whether this repository
is structured correctly for its purpose and whether the roadmap points it toward a coherent 1.0 release.

## Current Branch

- Repository: `swiftanvil/swiftanvil-anvil-runner`
- Branch: `fix/cleanup-and-conventions`
- Builder agent: Codex
- Review date: 2026-06-04

## Changes To Review

- Added `AGENTS.md`, `LICENSE`, and `ROADMAP.md`.
- Updated CI to use the current checkout action and PR trigger types.
- Updated README examples to prefer `ANVIL_RUNNER_TOKEN` over command-line token arguments.
- Added cleanup safety primitives:
  - `CleanupSafetyPolicy`
  - `CleanupResult`
  - `CleanupError`
  - cleanup allowlist/protected-root enforcement
  - dry-run reporting
- Removed broad default cleanup of `~/.docker`.
- Scoped ephemeral temp cleanup to runner-owned temp names.
- Removed shell interpolation from runner start.
- Replaced regex-style process termination/status checks with literal runner name plus runner-directory matching.
- Added runner-name/path validation to prevent path traversal through lifecycle commands.
- Added unregister-before-delete behavior for `remove`, with `--force-local` required for local-only deletion.
- Moved GitHub runner tokens from runner-script argv into `ACTIONS_RUNNER_INPUT_TOKEN`.
- Rejected broad `--allow-root` values and expanded protected roots for cleanup safety.
- Documented the current runner-supervision limitation and added LaunchAgent supervision to the roadmap.
- Added tests for cleanup safety, dry-run behavior, runner temp scoping, process matching, and runner path
  validation.

## Verification Already Run

- `swift test`
- `swift build`
- `../swiftanvil-enforcement/scripts/enforce-local.sh --registry-root ../swiftanvil-meta --root .`
- workflow YAML parse
- line-length scan for Swift, Markdown, YAML
- stale-token/stale-version scan

## Review Questions

1. Are filesystem deletion and process-signaling blast radii constrained enough for a release candidate?
2. Does the public API shape follow Swift API expectations for clarity and future evolution?
3. Is the current package/CLI structure appropriate, or should this be split into lower-level libraries and a
   separate operational CLI later?
4. Is the roadmap sufficiently complete for SwiftAnvil's intended use, especially config files, observability,
   runner upgrades, and organization-scope runners?
5. Are the local/CI enforcement hooks sufficient for this repository until org-level enforcement PRs are merged?
6. What remaining release blockers should be fixed before opening or merging the PR?

## Required Output

Return a concise but exhaustive review with:

- `VERDICT: APPROVED`, `VERDICT: CHANGES_REQUESTED`, or `VERDICT: BLOCKED`
- blocker findings first, with file paths and concrete fixes
- non-blocking risks and roadmap recommendations
- a short table summarizing release gates and pass/fail status
