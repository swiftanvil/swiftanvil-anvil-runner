# Changelog

All notable changes to AnvilRunner are documented here.

## Unreleased

- No changes yet.

## 0.1.0 - 2026-06-04

Initial SwiftAnvil release candidate.

- Add a Swift package and CLI for managing self-hosted GitHub Actions runners on macOS.
- Add safe cleanup policies with allowlisted roots, protected roots, and dry-run reporting.
- Add runner lifecycle commands for setup, start, stop, status, cleanup, and removal.
- Unregister runners from GitHub before deleting local runner directories.
- Pass runner registration and removal tokens through `ACTIONS_RUNNER_INPUT_TOKEN`.
- Add CI, review artifacts, release roadmap, and SwiftAnvil enforcement integration.
