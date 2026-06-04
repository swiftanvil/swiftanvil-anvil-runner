# AnvilRunner

Self-hosted GitHub Actions runner management for macOS.

## Overview

AnvilRunner is a Swift-based tool for managing self-hosted GitHub Actions runners on Apple Silicon Macs. It
handles installation, lifecycle management, automated cleanup, and health monitoring for solo developers and
small teams who want predictable local CI capacity without cloud-minute constraints.

## Features

- **One-command setup** — Install and configure multiple runner instances
- **Ephemeral mode** — Clean workspace after every job (default)
- **Automated cleanup** — Four policies from minimal to full wipe
- **Health monitoring** — Disk usage, memory, runner process status
- **Multi-instance** — Run 2–4 parallel runners on a single Mac Mini

## Installation

### As a Swift Package Dependency

Add to your `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YourProject",
    dependencies: [
        .package(
            url: "https://github.com/swiftanvil/swiftanvil-anvil-runner.git",
            from: "1.0.0"
        )
    ],
    targets: [
        .target(
            name: "YourTarget",
            dependencies: [
                .product(name: "AnvilRunner", package: "swiftanvil-anvil-runner")
            ]
        )
    ]
)
```

### CLI Tool (Standalone)

```bash
git clone https://github.com/swiftanvil/swiftanvil-anvil-runner.git
cd swiftanvil-anvil-runner
swift build -c release
```

The `anvil-runner` binary will be at `.build/release/anvil-runner`.

## Usage

### Setup

```bash
export ANVIL_RUNNER_TOKEN=<token>
anvil-runner setup --repo https://github.com/your-org/your-repo --count 2
```

### Start runners

```bash
anvil-runner start --count 2
```

### Check status

```bash
anvil-runner status --count 2
```

### Remove runners

```bash
export ANVIL_RUNNER_REMOVAL_TOKEN=<token>
anvil-runner remove --count 2
```

`remove` unregisters each runner with GitHub before deleting local files. Token precedence is `--token`,
`ANVIL_RUNNER_REMOVAL_TOKEN`, `ANVIL_RUNNER_TOKEN`, then `GITHUB_TOKEN`. Use `--force-local` only when the
GitHub-side runner has already been removed or the local configuration is unrecoverable.

### Clean up disk

```bash
anvil-runner clean --workspace ~/actions-runner/_work --dry-run
anvil-runner clean --aggressive
```

## Architecture

```
AnvilRunner
├── RunnerConfiguration.swift    # Configuration model with validation
├── RunnerLifecycle.swift        # Download, configure, start, stop, remove
├── CleanupPolicy.swift          # Cleanup strategies, safety scopes, dry-run results, and disk checks
└── HealthMonitor.swift          # Process status, disk, memory monitoring

AnvilRunnerCLI
└── main.swift                   # CLI entry point (setup, start, stop, status, clean)
```

## Requirements

- macOS 14+
- Swift 6.0+
- GitHub personal access token with `repo` scope
- GitHub Actions runner 2.334.0 by default

## Safety Model

AnvilRunner manages long-lived machines and can delete build artifacts, so cleanup is intentionally constrained:

- cleanup is only allowed under known runner/cache roots unless `--allow-root` is provided
- broad roots such as `/`, `/Users`, `/System`, and the home directory cannot be added with `--allow-root`
- protected roots such as `/`, the home directory, and the system temp directory are never deleted directly
- `--dry-run` reports cleanup actions without deleting files
- runner startup avoids shell interpolation
- runner shutdown matches literal runner names and directories before sending signals
- runner removal unregisters with GitHub before deleting local files unless `--force-local` is explicit
- runner registration and removal tokens are passed to GitHub's runner scripts through
  `ACTIONS_RUNNER_INPUT_TOKEN`, not command-line arguments

Prefer `ANVIL_RUNNER_TOKEN` over `--token` so credentials do not land in shell history.

## Current Limitation

`start` launches runner processes directly and does not yet install macOS LaunchAgents or another supervisor.
Use a persistent session or external supervisor for long-lived runner fleets until LaunchAgent support lands.

## License

MIT
