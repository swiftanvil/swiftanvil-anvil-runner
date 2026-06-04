# Managed Worker Vision

## Purpose

SwiftAnvil should provide one coherent user-facing workflow for turning a Mac into a safe, observable,
reusable Apple-platform worker.

The internal code may be split by concern over time, but the user should not need to understand the repository
layout to operate a worker.

## North Star

A contributor should be able to take a Mac mini or other Apple Silicon Mac and make it capable of:

- running GitHub Actions jobs
- running Swift builds and tests
- running Xcode builds and simulator tests
- running performance benchmarks
- exposing safe remote access through approved channels
- recovering after reboot or power loss
- advertising its capabilities through runner labels
- cleaning itself safely
- reporting health in human-readable and machine-readable forms

## Vocabulary

| Term | Meaning |
|------|---------|
| Worker | A managed machine that can run build, test, benchmark, or automation work. |
| Runner | A GitHub Actions runner process registered to a repository or organization. |
| Host | The local macOS system and its machine-level settings. |
| Capabilities | Detected properties that describe what work the machine can run. |
| Fleet | A group of workers managed together. |

## User-Facing Shape

The preferred user experience is a single command surface:

```text
anvil worker doctor
anvil worker provision
anvil worker status
anvil runner setup
anvil runner start
anvil runner stop
anvil runner remove
```

`anvil-runner` remains the current standalone executable for runner lifecycle work. The broader worker commands
can be introduced after the vocabulary and capability model stabilize.

## Internal Boundaries

- Runner lifecycle: GitHub runner setup, start, stop, status, cleanup, and removal.
  Keep this in AnvilRunner.
- Capability discovery: detect Xcode, Swift, SDKs, simulators, architecture, disk, RAM, and runner labels.
  Start here and extract only after another package needs it.
- Host readiness: read-only checks for SSH, Tailscale, power settings, Xcode license, and sleep risk.
  Start here as `doctor`; avoid mutation first.
- Host provisioning: mutating setup for SSH, power, LaunchAgents, Tailscale, and supervision.
  Add only after read-only checks are reliable.
- Fleet orchestration: multiple workers, drain, repair, upgrade, and remote execution.
  Defer until the one-worker flow is stable.

## Phase Plan

### Phase 0: Release Hygiene

- Add changelog, security policy, ownership, dependency update policy, and macOS support validation.
- Tag the first `0.1.0` release after release hygiene lands.

### Phase 1: Worker Vocabulary

- Keep this vision document current.
- Avoid new repositories until a second consumer makes extraction worthwhile.
- Use one user-facing command model in documentation and reviews.
- Decide whether the future `anvil` command is an umbrella executable, an alias, or part of `swiftanvil-cli`
  before adding user-facing worker commands.

### Phase 2: Capability Discovery

Add read-only detection for:

- macOS version
- CPU architecture
- RAM and disk space
- Swift version
- Xcode version
- installed SDKs
- available simulators
- GitHub runner installation
- SSH status
- Tailscale status

Output should support both human text and future JSON.

Define the JSON schema before `doctor` or provisioning commands consume capability data programmatically.

### Phase 3: Worker Doctor

Add read-only readiness checks:

- Xcode installed
- command line tools installed
- Xcode license accepted
- disk pressure
- sleep or power settings that can interrupt CI
- runner process status
- LaunchAgent supervision missing or configured
- cleanup safety configuration

This phase should not mutate the machine.

### Phase 4: Safe Provisioning

Add explicit, dry-run-capable provisioning:

- enable SSH or document why it is disabled
- configure restart after power loss
- configure sleep prevention for CI windows
- install LaunchAgent supervision
- verify Tailscale installation and authentication
- write runner logs to stable paths

Privileged operations must explain what will change before they run.

### Phase 5: Worker Profiles

Introduce a versioned profile file:

```yaml
worker:
  role: xcode-ci
  runner:
    count: 2
    repository: https://github.com/example-org/example-repo
    labels: auto
  remoteAccess:
    ssh: true
    tailscale: true
  power:
    restartAfterPowerFailure: true
    preventSleep: true
  capabilities:
    required:
      - swift-build
      - swift-test
      - xcode-build
      - ios-simulator
```

Support `validate`, `diff`, and `apply` flows before mutation-heavy automation.

### Phase 6: Fleet Management

After a single worker is reliable:

- list workers
- compare capabilities
- drain a worker
- rotate runner tokens
- upgrade runner binaries
- produce health reports
- support remote execution through approved access paths

## Non-Goals For Now

- Do not create separate public repositories before the internal boundaries are proven.
- Do not silently mutate host settings.
- Do not require one specific LLM agent, editor, or private machine layout.
- Do not make Tailscale or SSH mandatory for basic local runner operation.
- Do not hide privileged operations behind a broad setup command without a dry-run.
