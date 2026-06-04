# Agent Instructions

This repository contains AnvilRunner, the SwiftAnvil package for managing self-hosted GitHub Actions runners
on macOS.

## Rules

- Do not commit directly to `main`; use a feature branch and pull request.
- Keep runner lifecycle operations shell-free where possible.
- Do not interpolate user-controlled paths or names into shell commands.
- Cleanup code is safety-critical.
- New cleanup behavior must have tests for allowed paths, protected paths, and dry-run behavior.
- Prefer environment variables for credentials.
- Do not document command examples that encourage token leakage into shell history.
- Keep CI and enforcement workflows aligned with the current SwiftAnvil organization templates.
- Use `swift build`, `swift test`, and local SwiftAnvil enforcement before opening a PR.
- Public API changes should follow Swift API Design Guidelines and include documentation comments.

## Review Focus

Every substantive change should be reviewed for:

- filesystem deletion blast radius
- process matching and signal safety
- credential handling
- idempotence of setup/start/stop/remove operations
- test coverage for failure paths
- compatibility with self-hosted macOS runners
