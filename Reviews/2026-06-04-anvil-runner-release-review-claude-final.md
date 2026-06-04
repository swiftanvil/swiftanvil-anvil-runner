# AnvilRunner Release Readiness Review — Claude (Final)

- Branch: `fix/cleanup-and-conventions`
- Reviewer: Claude (Opus 4.7, 1M)
- Date: 2026-06-04
- Scope: re-review of the standalone library + CLI against the prior review's blockers
  (`Reviews/2026-06-04-anvil-runner-release-review-claude.md`) and the release gates in
  `ROADMAP.md`.

## VERDICT: APPROVED (for 0.1 tag); CHANGES_REQUESTED if tagged 1.0

The four blockers from the prior review are now either fixed in code or explicitly accepted with a
documented limitation banner and a roadmap home. The cleanup-safety primitives now correctly reject
broad `--allow-root` values, the lifecycle now unregisters from GitHub before deletion, and runner
tokens are passed through `ACTIONS_RUNNER_INPUT_TOKEN` rather than argv. The remaining issues are
non-blocking for a 0.1 SwiftAnvil-member tag but several would re-open as blockers if the same
artifact were tagged 1.0.

---

## Blocker Status (from prior review)

### B1 — `remove` does not unregister from GitHub — FIXED

`RunnerLifecycle.remove` at `Sources/AnvilRunner/RunnerLifecycle.swift:77–103` now calls
`removeRunnerConfiguration` (which spawns `config.sh remove` with the token in env) before
`removeItem`, gated on `forceLocal == false`. `--force-local` is required to skip and is documented
in README. The CLI accepts the removal token from `--token`, `ANVIL_RUNNER_REMOVAL_TOKEN`,
`ANVIL_RUNNER_TOKEN`, or `GITHUB_TOKEN`
(`Sources/AnvilRunnerCLI/main.swift:144–149`). One residual nit: when `config.sh` is missing the
code throws `configurationFailed` rather than a dedicated case — fine for 0.1 but consider a
`runnerScriptMissing` case before 1.0 so the operator message is unambiguous.

### B2 — `start` does not daemonize — DEFERRED + DOCUMENTED

`startRunner` at `Sources/AnvilRunner/RunnerLifecycle.swift:150–159` still calls `process.run()`
without `setpgid`/`setsid`, redirects stdout/stderr to `/dev/null`, and writes no PID/log files.
This was not fixed in this branch. It is, however, now (a) documented as a "Current Limitation" in
`README.md:132–135` and (b) placed in `ROADMAP.md` 0.5 ("Add macOS LaunchAgent supervision with
logs and restart policy"). That matches the prior review's exit criterion for shipping 0.1.

Action for the PR description: include a copy of the "Current Limitation" wording in the PR body
so reviewers / future operators see it before they install.

### B3 — `--allow-root` blast radius — FIXED

`CleanupSafetyPolicy` at `Sources/AnvilRunner/CleanupPolicy.swift:76–125` now:
- treats protected directories as prefix-matched (line 99–101), not exact-match;
- rejects "too broad" allowed roots — anything that is itself `/` or that contains a protected
  directory underneath it (lines 89–91, 116–124);
- exposes `allowsAdditionalRoot(_:)` so the CLI can refuse user input before constructing a policy
  (line 105–109).

The CLI calls this at `Sources/AnvilRunnerCLI/main.swift:208–211`, so `--allow-root /`,
`--allow-root /Users`, `--allow-root /System`, `--allow-root $HOME` all error with
`CleanupError.unsafePath`. Tests cover the rejection
(`Tests/AnvilRunnerTests/CleanupPolicyTests.swift:88–107`). One residual gap: there is no
end-to-end test that drives `cleanCommand` with `--allow-root /` through the CLI surface, only the
policy unit test. Add one in 0.2.

### B4 — Token in argv — FIXED

`installRunner` at `Sources/AnvilRunner/RunnerLifecycle.swift:131–148` no longer passes `--token`
to `config.sh`; instead `environment(addingRunnerToken:)` (line 282–286) sets
`ACTIONS_RUNNER_INPUT_TOKEN`, which the GitHub runner reads as a substitute for `--token`. The
remove path uses the same helper (line 179). `runnerDir` is chmod'd to `0700` after configuration
(line 147), which constrains `.credentials*` exposure. README documents the env-token preference
in the "Safety Model" section. Test at
`Tests/AnvilRunnerTests/RunnerLifecycleTests.swift:118–123` asserts the env var is set.

Residual: `RunnerConfiguration.token` is still a stored `String`
(`Sources/AnvilRunner/RunnerConfiguration.swift:8`). For 1.0, consider switching to a closure or a
distinct `RunnerCredential` type so accidental logging is harder. Non-blocking.

---

## Non-Blocking Risks

### API shape

- `start(installDirectory:count:namePrefix:)` / `stop(...)` / `remove(...)` repeat three of
  `RunnerConfiguration`'s fields. Introduce a `RunnerSelection` value (or accept the configuration
  directly) so the caller doesn't manually keep these in sync.
- `CleanupPolicy` (the strategy enum) and `CleanupSafetyPolicy` (the allow/protect struct) collide
  on the word "Policy." Rename the struct to `CleanupScope` or `CleanupSafetyConstraints` before
  1.0; once consumers depend on it the rename gets harder.
- `RunnerError` should conform to `LocalizedError` / `CustomStringConvertible`. The CLI currently
  prints `Error: processFailed(exitCode: 1)`, which is unhelpful at the operator surface
  (`Sources/AnvilRunnerCLI/main.swift:36`).
- `CleanupExecutor` is an actor but holds only the immutable `safetyPolicy`. It can be a struct
  with `nonisolated` async methods; the `actor` only adds scheduling overhead and forces every
  caller to `await`.
- `HealthMonitor.statuses` dictionary is written but never read
  (`Sources/AnvilRunner/HealthMonitor.swift:5,23`). Delete it.
- Several public methods (`RunnerLifecycle.start/stop/remove`, `CleanupExecutor.scheduledDeepClean`)
  lack doc comments describing idempotency and failure semantics. Required by 1.0 under the
  Swift API Design Guidelines.

### Test coverage

- No tests exercise `RunnerLifecycle.setup` / `start` / `stop` / `remove` end-to-end. Inject a
  `ProcessRunner` protocol and a `FileManager`-shaped fake; drive the actor against a fixture tree.
  This is the single highest-leverage gap before 1.0.
- `CleanupPolicy.aggressive/ephemeral/standard` are only tested at the raw-value level; add a
  temp-tree test that runs each strategy and asserts removed-vs-retained sets.
- `HealthMonitorTests` only covers `formatReport`. Inject a disk/memory provider so
  `isDiskCritical`/`isMemoryCritical` thresholds are tested deterministically.
- Add a CLI-surface test for `--allow-root /` and `--allow-root $HOME` so B3 is regression-protected
  at the command level, not only the policy unit.

### Package structure

The current single-library + single-executable shape is correct for 0.1. The natural split (once
0.2 / config files lands) is `AnvilRunnerCore` (config + policy + result + errors), `AnvilRunnerOps`
(`Lifecycle`, `Executor`, `Monitor` behind a `ProcessRunner`), and `AnvilRunnerCLI`. Don't split
eagerly — wait for the second consumer.

### CLI / argument parsing

- Hand-rolled `extractOption` is brittle: `--count=2` is silently ignored, repeated flags are
  ignored, and `-c` will collide with future flags. Adopt `swift-argument-parser` in 0.2 (already
  on the roadmap).
- `setupCommand` falls back to interactive `prompt(...)` for `--repo` and `--token` if not
  provided. Consider adding a `--token-stdin` mode so callers can pipe from a secret manager
  (`gh auth token | anvil-runner setup --token-stdin ...`).
- `cleanCommand` calls `executor.diskUsagePercent()` after a dry-run; printing
  "Disk usage: 73%" after a no-op clean reads like a real result. Skip the `df` call when
  `--dry-run` is set.

### CI / enforcement

- `runs-on: macos-latest` is unpinned; the image rolls forward silently and drifts away from the
  developer environment. Pin to `macos-15` (or `macos-14`) and run a small Xcode matrix before 1.0.
- Add a `swift --version` / `xcodebuild -version` step so failures are reproducible from logs.
- No `swift-format` / `swiftlint` step. Acceptable until the org template merges; track in ROADMAP
  alongside 0.2.
- `document-registry-policy-check` references `@v1`. Confirm that tag exists in
  `swiftanvil-enforcement` and is pinned to a SHA in the registry — a moving major ref undermines
  the rest of the enforcement story.
- `actions/checkout@v6` — verify the major exists at tag-time; v4 is the long-stable line. If v6
  is not yet released, downgrade to `@v4` rather than fail-closed in CI.

### Documentation

- README "Safety Model" should explicitly call out the (now prefix-based) protected-directory
  check and the rejection rules for `--allow-root`. Today users have to read the code to know
  what's rejected.
- README "Architecture" still omits `CleanupSafetyPolicy` / `CleanupResult` from the per-file
  callouts (they live in `CleanupPolicy.swift` but are the public surface most consumers will
  touch).
- README does not document `ANVIL_RUNNER_REMOVAL_TOKEN` precedence vs. `ANVIL_RUNNER_TOKEN` for the
  remove flow — the CLI silently falls back. Make the precedence explicit.

### Roadmap

The roadmap is well-shaped. A few additions implied by the product framing:
- **0.3** — explicitly call out **JIT registration-token rotation** and a `runnerScriptMissing`
  recovery flow.
- **0.4** — `--json` output for `status` / `clean` is what makes the tool "agent-friendly"; name
  it in 0.4 rather than implying it under "machine-readable status output."
- **0.5** — name **per-runner targeting** (`anvil-runner stop --name macmini-2`) alongside
  LaunchAgent supervision. Targeting by count alone is the biggest current ergonomic gap.
- **1.0** — add an explicit **security-review** gate (token handling, filesystem ACLs, signal
  handling). The current "sibling-host implementation review" line implies this but doesn't name
  it as a separable activity.

---

## Release Gates

| Gate                                                  | Status     | Notes |
|-------------------------------------------------------|------------|-------|
| Cleanup safety — allowlist + protected + dry-run      | ✅ Pass    | Protected check is now prefix-based; `--allow-root` rejects broad roots; tests cover both. |
| Lifecycle safety — shell-free + literal process match | ✅ Pass    | `pgrep` + literal-name + directory-boundary match is correct and covered. |
| Lifecycle correctness — clean uninstall               | ✅ Pass    | `config.sh remove` runs before deletion; `--force-local` is the explicit escape hatch. |
| Lifecycle correctness — supervision / daemonization   | ⚠️ Deferred | Not fixed; documented as "Current Limitation"; scheduled in ROADMAP 0.5. Acceptable for 0.1, blocking for 1.0. |
| Credential safety — env-token preferred & no argv leak | ✅ Pass    | Token flows through `ACTIONS_RUNNER_INPUT_TOKEN`; `runnerDir` chmod'd `0700`; tested. |
| CI — build + test + policy workflow                   | ⚠️ Partial | Wired; image not pinned; checkout major and policy `@v1` tag should be verified before tagging. |
| Documentation — setup / cleanup / safety / recovery   | ⚠️ Partial | Setup, clean, safety model, supervision limitation present; remove-token precedence and architecture callouts incomplete. |
| Review — PR provenance & sibling-host review          | ✅ Pass    | AGENTS.md + this review satisfy 0.1 process expectations. |
| Roadmap completeness                                  | ⚠️ Partial | Good shape; missing explicit JSON output, per-runner targeting, JIT token rotation, security-review gate. |
| Test coverage — pure helpers                          | ✅ Pass    | Cleanup safety, dry-run, process-list filtering, path traversal all covered. |
| Test coverage — orchestration                         | ❌ Fail    | No tests for `setup`/`start`/`stop`/`remove` orchestration or per-policy cleanup behavior. Non-blocking for 0.1, blocking for 1.0. |

---

## Answers to Review Questions

1. **Filesystem & process blast radius.** Filesystem is constrained enough for an RC: protections
   are prefix-matched, `--allow-root` is policed by `allowsAdditionalRoot`, and the temp wipe is
   scoped to runner-owned prefixes. Process signaling is correctly scoped by literal name + path
   boundary. Adequate for 0.1.
2. **Public API shape.** Mostly fine; the `start/stop/remove` parameter triple, the
   `CleanupPolicy` / `CleanupSafetyPolicy` name overlap, and `RunnerError`'s missing
   `LocalizedError` conformance are the three API-debt items worth fixing before 1.0.
3. **Package / CLI structure.** Right for 0.1. Plan the `Core` / `Ops` / `CLI` split for 0.2 once
   the config-file loader gives the split a real reason. Do not split eagerly.
4. **Roadmap completeness.** Sufficient. Add: JIT token rotation (0.3), `--json` output (0.4),
   per-runner targeting alongside LaunchAgents (0.5), explicit security-review gate (1.0).
5. **Local / CI enforcement.** Sufficient as a stopgap. Pin `macos-15`, verify
   `actions/checkout@v6` and `document-registry-policy@v1`, and fold the workflow into the shared
   template once org-level enforcement merges.
6. **Remaining release blockers.** None blocking a 0.1 tag. B2 (supervision) remains the single
   blocker for a 1.0 tag, joined by orchestration test coverage and the API-shape cleanup. The
   small items (HealthMonitor unused state, dry-run skipping `df`, README architecture callouts,
   removal-token precedence docs) are worth folding into this PR if it's quick — none are
   blocking.

---

## Summary

This branch closes three of the four prior blockers (B1, B3, B4) and explicitly accepts B2 with a
documented limitation and a roadmap home. That matches the bar the prior review set for a 0.1 tag.
Merge as 0.1. The work remaining for a credible 1.0 — supervision, orchestration tests, API-shape
cleanup, JSON output — is on the roadmap and should be scoped against subsequent milestones rather
than bundled into this PR.
