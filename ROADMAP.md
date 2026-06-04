# AnvilRunner Roadmap

## Vision

AnvilRunner should be the SwiftAnvil control plane for small self-hosted macOS runner fleets. The goal is not
to replace GitHub Actions; it is to make Apple-platform CI predictable, observable, and safe for solo developers
and small teams that need more control than hosted minutes provide.

## Product Principles

- Safety before convenience: cleanup must be constrained, inspectable, and reversible where possible.
- Local-first operation: a maintainer should be able to install, inspect, repair, and remove runners from one
  machine without a hosted service.
- GitHub-native integration: runner registration, labels, and lifecycle should stay compatible with GitHub's
  supported runner model.
- Agent-friendly workflows: automation agents should be able to reason from structured configuration and
  dry-run outputs.

## Release Gates

| Gate | Required Before 1.0 |
|------|---------------------|
| Cleanup safety | Allowlisted deletion, protected roots, dry-run, and tests |
| Lifecycle safety | Shell-free process launch and literal runner process matching |
| Credential safety | Environment-token path documented as preferred |
| CI | Swift build/test plus SwiftAnvil policy workflow |
| Documentation | Setup, cleanup, safety model, and operational recovery notes |
| Review | PR provenance and sibling-host review |

## Milestones

### 0.1: Safe Standalone Package

- Swift package builds and tests on macOS.
- Cleanup safety model is implemented.
- CI and organization standards are present.
- README documents safe setup and cleanup.

### 0.2: Configuration File Support

- Add a versioned YAML or JSON config file for fleets.
- Support labels, runner count, install directory, cleanup policy, and disk thresholds.
- Validate config before any mutation.
- Adopt Swift Argument Parser for typed commands and stronger CLI validation.
- Add swift-format and SwiftLint checks once the organization template is merged.

### 0.3: Runner Registration Hardening

- Fetch or validate runner versions explicitly.
- Verify runner archive checksums when GitHub publishes them.
- Support repository and organization runner scopes.
- Support short-lived registration and removal token rotation.
- Add idempotent setup for already-configured runners.

### 0.4: Observability

- Emit machine-readable status output.
- Add `--json` output for status, cleanup, and future repair commands.
- Add health checks for stale jobs, disk pressure, missing runner binaries, and stopped listeners.
- Add structured logs for cleanup actions.

### 0.5: Fleet Operations

- Add repair and rotate commands.
- Add safe upgrade flow for GitHub runner binaries.
- Add macOS LaunchAgent supervision with logs and restart policy.
- Add per-runner targeting for start, stop, status, clean, and remove.
- Add backup/restore of runner metadata that is safe to keep locally.

### 1.0: SwiftAnvil Release

- Complete public API documentation.
- Add integration tests with fake runner directories and process fixtures.
- Complete security review for token handling, filesystem permissions, and signal handling.
- Add release notes and semantic version tag.
- Complete sibling-host implementation review.
