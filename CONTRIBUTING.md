# Contributing

Follow the organization contribution guide identified by `org.contributing` in the SwiftAnvil document
registry.

## Local Setup

Clone the package next to the shared enforcement and registry repositories:

```text
swiftanvil/
├── swiftanvil-anvil-runner/
├── swiftanvil-enforcement/
└── swiftanvil-meta/
```

Before opening a PR, run:

```bash
swift build
swift test
Scripts/enforce-local.sh
```

Substantive changes need independent review artifacts under `Reviews/` and a completed Review Provenance
table in the PR body.
