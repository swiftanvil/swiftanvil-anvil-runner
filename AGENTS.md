# Agent Instructions — AnvilRunner

> **For AI Agents:** This file is your control program. Read it, then execute.

## Mission

Manage self-hosted GitHub Actions runners on this Mac. Download, configure, start, stop, clean up.

## What You Must Do First

```bash
swift build -c release 2>/dev/null || swift build
./.build/release/anvil-runner
```

The binary will tell you the current state and what actions are available. Do not guess — always run this first.

## How to Execute Actions

```bash
./.build/release/anvil-runner agent <action-id>
```

Available action IDs depend on current state. The binary lists them. Common ones:
- `doctor` — health checks
- `discover` — scan host capabilities
- `setup` — configure runners for a repo (requires `--repo` and `--token`)
- `start` — start runners
- `status` — check runner health
- `clean` — free disk space

## Rules

- **Never** pass tokens as command-line arguments. Use `--token` only if the user provides it. Prefer `ANVIL_RUNNER_TOKEN` environment variable.
- **Always** run the binary with no args before making decisions. State changes after every action.
- **Ask** the user for their GitHub token and repo URL. Do not guess.
- **Confirm** before `remove` or `clean --aggressive`. These are destructive.

## State Reference

| State | Meaning | What to do |
|-------|---------|-----------|
| `fresh-clone` | Not built | `swift build -c release` |
| `built` | Binary ready, no runners | `agent discover`, then `agent setup` |
| `configured` | Runners ready, not started | `agent start` |
| `running` | Runners active | `agent status`, `agent stop` |
| `stopped` | Runners paused | `agent start`, `agent remove` |

## Handoff

After `setup` + `start` succeeds, report:
1. What was done (runners configured, repo registered)
2. Current state
3. How to check status: `agent status`
4. How to add more repos: run `agent setup` again with different `--repo`
