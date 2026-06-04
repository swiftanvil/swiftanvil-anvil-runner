# Security Policy

## Supported Versions

Security fixes are provided for the latest released `0.x` version until the first stable `1.0` release.

## Reporting a Vulnerability

Report security issues privately through GitHub Security Advisories when available. If advisories are not
enabled, contact the repository owner directly before opening a public issue.

Do not include active GitHub tokens, runner registration tokens, machine hostnames, Tailscale node names, or
private network details in public issues.

## Security-Sensitive Areas

AnvilRunner changes require extra care when they affect:

- GitHub runner registration or removal tokens
- filesystem deletion and cleanup scopes
- process matching and signal handling
- runner directory permissions
- future remote access, host provisioning, or supervision behavior
