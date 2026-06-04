# AnvilRunner

Self-hosted GitHub Actions runner management for macOS.

## Overview

AnvilRunner is a Swift-based tool for managing self-hosted GitHub Actions runners on Apple Silicon Macs. It handles installation, lifecycle management, automated cleanup, and health monitoring — designed for solo developers and small teams who want unlimited CI minutes without cloud costs.

## Features

- **One-command setup** — Install and configure multiple runner instances
- **Ephemeral mode** — Clean workspace after every job (default)
- **Automated cleanup** — Four policies from minimal to full wipe
- **Health monitoring** — Disk usage, memory, runner process status
- **Multi-instance** — Run 2–4 parallel runners on a single Mac Mini

## Installation

```bash
git clone https://github.com/swiftanvil/swiftanvil-anvil-runner.git
cd swiftanvil-anvil-runner
swift build -c release
```

## Usage

### Setup

```bash
anvil-runner setup --repo https://github.com/v-i-s-h-a-l/iStudio --token ghp_xxx --count 2
```

### Start runners

```bash
anvil-runner start --count 2
```

### Check status

```bash
anvil-runner status --count 2
```

### Clean up disk

```bash
anvil-runner clean --aggressive
```

## Requirements

- macOS 14+
- Swift 6.0+
- GitHub personal access token with `repo` scope

## License

MIT
