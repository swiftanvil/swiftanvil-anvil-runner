# AnvilRunner Release Readiness Review — Claude

- Branch: `fix/cleanup-and-conventions`
- Reviewer: Claude (Opus 4.7, 1M)
- Date: 2026-06-04
- Scope: standalone-library + CLI release readiness; plan + implementation direction.

## VERDICT: CHANGES_REQUESTED

The cleanup-safety and process-matching primitives are a real improvement and the AGENTS / ROADMAP /
LICENSE / CI plumbing are appropriate for a SwiftAnvil-member repository at 0.1. The package is structurally
sound for its scope and the roadmap maps cleanly to a 1.0. However, there are concrete release-blocking
gaps in the **lifecycle** half of the product (GitHub-side de-registration, supervision/daemonization, the
`--allow-root` escape hatch, and token exposure via argv) that should be closed — or explicitly deferred
with a documented limitation — before this is tagged as a SwiftAnvil-supported release.

---

## Blocker Findings

### B1. `remove` deletes runner directories without unregistering from GitHub

**Where:** `Sources/AnvilRunner/RunnerLifecycle.swift:77–89`, `Sources/AnvilRunnerCLI/main.swift:131–159`

`RunnerLifecycle.remove` simply `removeItem`s the runner directory after a safety check. The standard
self-hosted runner uninstall flow is `./config.sh remove --token <REMOVAL_TOKEN>`; skipping it leaves an
orphan runner registered on GitHub's side, and the next `setup` against the same name fails because the
name is taken. For a tool that frames itself as "lifecycle management" this is the single most user-visible
correctness gap.

**Fix:**
- Before deleting `runnerDir`, invoke `config.sh remove --token <token>` via the same
  `runProcess` helper used by `installRunner`.
- Accept the removal token from `RunnerConfiguration` / CLI (env preferred — e.g. `ANVIL_RUNNER_REMOVAL_TOKEN`).
- If the unregister call fails, surface the error and *do not* delete the directory unless a `--force`
  flag is set; otherwise users lose the ability to retry cleanly.

### B2. `start` does not daemonize — runners share the CLI's process group

**Where:** `Sources/AnvilRunner/RunnerLifecycle.swift:134–143`

`startRunner` simply `process.run()`s `run.sh` and returns. The spawned `Runner.Listener` inherits the CLI's
controlling terminal and process group. When the CLI exits, behaviour depends on the parent shell:
under interactive zsh / a terminal session the children typically continue, but under `ssh some-host
'anvil-runner start ...'`, under launchd, or under any caller that sends `SIGHUP` to the process group on
exit, the runners are killed. There is also no PID file, no log file (stdout/err are redirected to
`/dev/null`, so diagnosing crashes is impossible), and no way for `stop`/`status` to know which run was
ours other than process-list pattern matching.

For a fleet-management tool that claims "predictable local CI capacity," this is structurally wrong.

**Fix (pick one):**
- **Recommended for 1.0:** generate a per-runner `~/Library/LaunchAgents/com.swiftanvil.anvil-runner.<name>.plist`
  and load it with `launchctl bootstrap gui/$(id -u)`. This gives macOS-native restart, log paths, and
  status. `stop`/`remove` then `bootout` the agent.
- **Minimum to ship 0.1:** `setsid` / explicit `setpgid` on the child, redirect stdout/stderr to a
  per-runner log file under `runnerDir/_diag/`, write a PID file, and have `stop`/`status` consult it
  before falling back to `pgrep`.

Until one of these lands, document the limitation prominently in `README.md` ("AnvilRunner does not yet
supervise runners — pair with a `launchd` agent or `tmux`/`screen` session").

### B3. `--allow-root` widens cleanup blast radius without any guard rails

**Where:** `Sources/AnvilRunnerCLI/main.swift:194–205`; `Sources/AnvilRunner/CleanupPolicy.swift:71–86`

`CleanupSafetyPolicy.allowsRemoval` checks `protectedDirectories.contains(candidate)` — i.e. *exact match
only*. The allowlist check, by contrast, is prefix-based. That asymmetry is fine as long as the allowlist
is curated, but `--allow-root` lets users append *any* path, including `/`, `$HOME`, or `/System`. The
exact-match protected check then only blocks a literal `rm -rf /` on the root itself — `--allow-root /`
combined with a workspace like `/Users` (or, with the aggressive policy, the `~/.build` path that the
executor itself generates) would happily remove sub-trees outside any runner-owned area.

**Fix:**
- Reject any `--allow-root` whose standardized path is `==` or `hasPrefix` of any protected directory, or
  is exactly `/`, `$HOME`, `/System`, `/Library`, `/Applications`, `/private`, or `/Users`.
- Make the protected check itself prefix-based (`candidate == protected || candidate.hasPrefix(protected + "/")`)
  so that protections actually cover descendants. With that change, even an `--allow-root /` is rendered
  inert because every candidate falls under `/` which itself becomes protected.
- Add a test that drives `--allow-root /` end-to-end and asserts `CleanupError.unsafePath` is thrown.

### B4. Tokens still land in `ps` output via `config.sh --token <value>`

**Where:** `Sources/AnvilRunner/RunnerLifecycle.swift:117–131`; `README.md:106–116`

The README correctly steers users to `ANVIL_RUNNER_TOKEN`, but the implementation still spawns
`config.sh --url ... --token <token> --name ...`. On macOS, argv is visible to other local users via `ps`
for the duration of `config.sh`'s execution. The safety-model section of the README claims credentials
are handled carefully; this nuance is currently invisible to users.

**Fix:**
- `config.sh` accepts `--token` only, but the underlying registration also accepts a JIT token via stdin
  when invoked with `--token -` in recent runner releases (≥ 2.317). Pipe the token through `standardInput`
  rather than placing it in argv. If pinning to 2.334.0, verify support there.
- If stdin injection isn't available, at minimum (a) document the residual exposure in the Safety Model
  section, (b) chmod the runner dir to `0700` after configuration so the stored `.credentials` file isn't
  world-readable.
- Treat `RunnerConfiguration.token` as sensitive: do not log, do not include in `description`, and
  consider switching the property to a `() -> String` closure or a discrete `RunnerCredential` type so
  accidental logging at the call site is harder.

---

## Non-Blocking Risks

### API shape (Swift API Design Guidelines)

- `RunnerLifecycle.start/stop/remove(installDirectory:count:namePrefix:)` repeats three parameters that
  are already in `RunnerConfiguration`. Introduce a `RunnerSelection` (or accept `RunnerConfiguration`
  directly) so the API doesn't degrade after `setup`. Currently the caller has to remember to keep the
  three values in sync between calls.
- `CleanupPolicy` (enum, the four strategies) and `CleanupSafetyPolicy` (struct, the allow/protect
  constraints) collide on the word "Policy." Rename the struct to `CleanupSafetyConstraints` or
  `CleanupScope` to remove the ambiguity at the call site. The enum is the more discoverable name.
- `RunnerError` should conform to `LocalizedError`/`CustomStringConvertible`. Today the CLI prints
  `Error: processFailed(exitCode: 1)`, which is unhelpful at the operator surface.
- `CleanupExecutor` does not actually need to be an `actor` — all of its state is the immutable
  `safetyPolicy`. Making it a `struct` with `nonisolated` methods removes scheduling overhead and lets
  callers compose it without `await`. Keep it an actor only if you intend to add stateful tracking
  (e.g., audit log).
- `HealthMonitor.statuses` dictionary is written but never read; it can be removed without externally
  visible effect.
- Add doc comments to the public types — `CleanupSafetyPolicy`, `CleanupResult`, `RunnerLifecycle`'s
  methods — at the level expected by Swift API guidelines. The current ones are good but uneven (e.g.
  `start(installDirectory:count:namePrefix:)` doesn't document idempotency or what happens if a runner is
  already running).

### Test coverage

- No tests exercise `RunnerLifecycle.setup` / `start` / `stop` / `remove` end-to-end. The pure helpers
  (`runnerProcessIDs(from:)`, `runnerDirectory(named:under:)`, `isRunnerTemporaryItem`) are well covered,
  but the orchestration is not. Inject a `ProcessRunner` protocol (or a `FileManager`-equivalent fake) and
  drive the actor against fixtures so the install/configure/uninstall sequence is verified.
- `CleanupPolicy.aggressive/ephemeral/standard` are tested only at the raw-value level. Add tests that
  build a temp directory tree, run each strategy against a synthesized `CleanupSafetyPolicy`, and assert
  which files were removed vs. retained.
- `HealthMonitorTests` only verifies `formatReport`. Add a fake disk/memory provider so
  `isDiskCritical`/`isMemoryCritical` thresholds are tested deterministically.
- Add a property-style test for `CleanupSafetyPolicy.allowsRemoval` that asserts every protected path and
  every common sibling of an allowed root is denied. This is the single highest-leverage safety test.

### Package structure

The current single-library + single-executable shape is correct for 0.1. Do *not* split eagerly. Once
0.2 (config files) lands the natural split is:
- `AnvilRunnerCore` — `RunnerConfiguration`, `CleanupPolicy`, `CleanupSafetyPolicy`, errors, result types.
- `AnvilRunnerOps` — `RunnerLifecycle`, `CleanupExecutor`, `HealthMonitor`, the `Process` + `FileManager`
  side effects, behind a `ProcessRunner` protocol.
- `AnvilRunnerCLI` — the operational CLI, switched to `swift-argument-parser`.

Defer that split until at least one external consumer exists; premature module boundaries here would just
slow iteration.

### CLI / argument parsing

- Hand-rolled `extractOption` is brittle (`--count 2 --name foo` works, `--count=2` doesn't, repeated
  flags are silently ignored, `-c` collides with the future `--cleanup-policy`). Adopt
  `swift-argument-parser` before 0.2 — the per-command structure also gives you typed enums for
  `CleanupPolicy`, which removes the `aggressive ? .aggressive : .standard` branches at every call site.
- `setupCommand` falls back to interactive `prompt` for both `--repo` and `--token` if not provided. For
  `--token` this is benign (input is on a tty), but consider adding a `--token-stdin` mode for piping from
  a secret manager (`gh auth token | anvil-runner setup --token-stdin ...`).
- `cleanCommand` invokes `executor.diskUsagePercent()` after cleanup. In `--dry-run` mode it still calls
  `df` even though nothing was deleted, which is fine but should be skipped to avoid confusing operators
  ("disk usage: 73%" after a no-op clean reads like a regression).

### CI / enforcement

- `macos-latest` pins to whichever Xcode image GitHub ships this week. Pin the runner image
  (`macos-15`, `macos-14`) and run a matrix over Xcode versions you support; otherwise the CI green light
  drifts away from the developer environment over time.
- Add a `swift package --version` and `xcodebuild -version` step at the top of the workflow so failures
  are reproducible from logs.
- No `swift-format` / `swiftlint` step. With SwiftAnvil-wide enforcement merging soon this can wait, but
  add a TODO in `ROADMAP.md` so it isn't forgotten.
- The `document-registry-policy-check` workflow is `uses: …@v1` — confirm that tag exists in
  `swiftanvil-enforcement` and is pinned to a SHA in the registry, not a moving ref.

### Roadmap

The roadmap is well-shaped but is missing a handful of items implied by the product framing:
- **0.3** — runner-binary checksum verification is mentioned, but **GitHub-side unregistration on remove**
  (B1) belongs here explicitly. Same for **registration-token rotation** (the short-lived JIT tokens,
  not the long-lived PAT).
- **0.4** — observability should call out a **structured JSON output mode** (`--json`) for `status` and
  `clean`; that's what makes the tool "agent-friendly" per the principles section, more than logs alone.
- **0.5** — fleet operations should call out **macOS supervision integration (LaunchAgents)** explicitly
  (B2). Also: **per-runner labels and selective targeting** (`anvil-runner stop --name macmini-2` rather
  than `--count`), which is a real ergonomic gap today.
- **1.0** — add **security review** as an explicit gate (token handling, filesystem ACLs on the runner
  dir, signal-handling). The current "sibling-host implementation review" line implies this but doesn't
  name it.

### Documentation

- README "Safety Model" should explain the asymmetry between allowed roots (prefix) and protected roots
  (currently exact-match) and what `--allow-root` widens. Once B3 is fixed, update accordingly.
- README does not document `remove` / `uninstall`. Given that B1 is currently broken, add the section
  *and* call out the GitHub-side state until the fix lands.
- `Architecture` block in the README omits `CleanupSafetyPolicy` and `CleanupResult`. Add them; that's
  the public surface most users will touch.

---

## Release Gates

| Gate                                                  | Status            | Notes |
|-------------------------------------------------------|-------------------|-------|
| Cleanup safety — allowlist + protected + dry-run      | ⚠️ Partial        | Solid primitives; `--allow-root` and exact-match protected check leave residual blast radius (B3). |
| Lifecycle safety — shell-free + literal process match | ✅ Pass           | Good improvement; `pgrep`+name+path-boundary matching is correct and covered. |
| Lifecycle correctness — clean uninstall               | ❌ Fail           | `remove` does not call `config.sh remove`; leaves stale GitHub registration (B1). |
| Lifecycle correctness — supervision / daemonization   | ❌ Fail           | `start` does not daemonize; no PID/log files (B2). |
| Credential safety — env-token preferred & no argv leak | ⚠️ Partial       | README + CLI prefer env; token still passed to `config.sh` via argv (B4). |
| CI — build + test + policy workflow                   | ✅ Pass           | Wire-up is correct; pin macOS image + Xcode before 1.0 (non-blocking). |
| Documentation — setup / cleanup / safety / recovery   | ⚠️ Partial        | Setup + clean covered; recovery, uninstall, and safety nuances missing. |
| Review — PR provenance & sibling-host review          | ✅ Pass (process) | AGENTS.md + this review satisfy the 0.1 expectations. |
| Roadmap completeness                                  | ⚠️ Partial        | Add GitHub-side unregistration, JSON output, LaunchAgents, security-review gate. |
| Test coverage — pure helpers                          | ✅ Pass           | Cleanup safety, dry-run, process-list filtering, path traversal all covered. |
| Test coverage — orchestration                         | ❌ Fail           | No tests for `setup`/`start`/`stop`/`remove` or per-policy cleanup behavior (non-blocking for 0.1, blocking for 1.0). |

---

## Summary

The diff on this branch is a net safety improvement and the standards artifacts (AGENTS / ROADMAP / LICENSE
/ CI updates / README env-token preference) are appropriate for shipping a SwiftAnvil-member 0.1. I would
merge the branch as 0.1 with B3 and B4 fixed in this PR (both are small, contained, and already
half-implemented) and a documented limitation banner in the README covering B1 and B2 until they land in
0.3 / 0.5 respectively.

If the tag being prepared is **1.0** rather than **0.1**, then B1 and B2 must land first — a 1.0 that
strands runner registrations on GitHub or that loses its child processes on shell exit isn't a 1.0 in any
meaningful sense.

### Answers to review questions

1. **Filesystem & process blast radius:** Filesystem is *almost* there — fix B3 and make the protected
   check prefix-based and it is release-ready. Process signaling is correctly scoped now.
2. **Public API shape:** Mostly fine; the start/stop/remove parameter triple and the `CleanupPolicy` vs.
   `CleanupSafetyPolicy` name overlap are the two API-debt items worth fixing before 1.0.
3. **Package/CLI structure:** Right for 0.1. Plan the `Core` / `Ops` / `CLI` split for 0.2 once a second
   consumer (config-file loader) creates a real reason for it. Don't split eagerly.
4. **Roadmap completeness:** Close enough; add GitHub-side unregistration to 0.3, JSON output to 0.4,
   LaunchAgents to 0.5, and security-review gate to 1.0.
5. **Local/CI enforcement:** Sufficient as a stopgap. Once org-level enforcement merges, fold this
   workflow into the shared template and drop the local-only bits.
6. **Release blockers:** B1 (unregister on remove), B2 (supervision/daemonization), B3 (`--allow-root`
   guard + prefix-based protection), B4 (token via argv). B3 and B4 are small enough to fix in this PR;
   B1 and B2 are scoped to follow-up milestones if the tag is 0.1, but become blockers for 1.0.
