# Agent Instructions — AnvilRunner

> **For AI Agents:** This file is your primary guide. Read it fully before taking action. It contains state detection, progressive workflows, and safety rules.

## What This Repository Does

AnvilRunner is a Swift library + CLI for managing self-hosted GitHub Actions runners on macOS. It downloads, configures, starts, stops, and cleans up GitHub Actions runners — safely.

**It does NOT:**
- Install LaunchAgents or auto-start on boot (that's `swiftanvil-anvil-host`)
- Configure Tailscale, power settings, or system policy
- Manage fleets of machines

## Current State Detection

When you open this repository, detect the current state:

```bash
# Check if binary exists
ls .build/release/anvil-runner 2>/dev/null && echo "built" || echo "not built"

# Check if runners are configured
ls ~/actions-runner/*/run.sh 2>/dev/null && echo "runners configured" || echo "no runners"

# Check if runners are running
pgrep -fl "Runner.Listener" && echo "running" || echo "not running"
```

## What You Can Do Here — Progressive Options

### State: Fresh Clone (nothing built)

**Option 1: Build the project**
> "Build anvil-runner"
```bash
swift build -c release
```

**Option 2: Run tests**
> "Run tests"
```bash
swift test
```

**Option 3: Explore capabilities**
> "What can this machine do?"
```bash
swift run anvil-runner discover
```

---

### State: Built (binary exists)

**Option 1: Set up runners for a repository**
> "Set up runners for my repo"
> Prerequisites: GitHub personal access token with `repo` scope
```bash
export ANVIL_RUNNER_TOKEN=<token>
.build/release/anvil-runner setup --repo https://github.com/<org>/<repo> --count 2
```

**Option 2: Check system health**
> "Run health checks"
```bash
.build/release/anvil-runner doctor
```

**Option 3: Clean up disk**
> "Clean up build artifacts"
```bash
.build/release/anvil-runner clean --aggressive
```

---

### State: Runners Configured

**Option 1: Start runners**
> "Start the runners"
```bash
.build/release/anvil-runner start --count 2
```

**Option 2: Check runner status**
> "Are my runners healthy?"
```bash
.build/release/anvil-runner status --count 2
```

**Option 3: Stop runners**
> "Stop the runners"
```bash
.build/release/anvil-runner stop --count 2
```

**Option 4: Remove runners**
> "Remove all runners"
```bash
export ANVIL_RUNNER_REMOVAL_TOKEN=<token>
.build/release/anvil-runner remove --count 2
```

---

## Common Workflows

### Workflow: First-Time Setup
```bash
swift build -c release
.build/release/anvil-runner doctor
# Fix any issues reported
export ANVIL_RUNNER_TOKEN=<token>
.build/release/anvil-runner setup --repo https://github.com/<org>/<repo> --count 2 --name macmini
.build/release/anvil-runner start --count 2
```

### Workflow: Nightly Cleanup
```bash
.build/release/anvil-runner clean --aggressive
.build/release/anvil-runner status --count 2
```

### Workflow: Upgrade Runner Version
```bash
# Stop current runners
.build/release/anvil-runner stop --count 2
# Remove old runners
export ANVIL_RUNNER_REMOVAL_TOKEN=<token>
.build/release/anvil-runner remove --count 2
# Set up new version (downloads latest)
export ANVIL_RUNNER_TOKEN=<token>
.build/release/anvil-runner setup --repo https://github.com/<org>/<repo> --count 2
.build/release/anvil-runner start --count 2
```

---

## Handoff Notes

After any action, report:
1. **What was done** (commands executed, outputs)
2. **Current state** (runners running? disk usage?)
3. **Next options** (based on new state)

Example handoff:
> ✅ Setup complete. 2 runners configured for `org/repo`.
>
> **Current state:** Runners not yet started. Disk: 45% used.
>
> **Next options:**
> 1. Start runners now
> 2. Check system health first
> 3. Configure auto-start on boot (requires `swiftanvil-anvil-host`)

---

## Safety Rules

- Do not commit directly to `main`; use a feature branch and pull request.
- Keep runner lifecycle operations shell-free where possible.
- Do not interpolate user-controlled paths or names into shell commands.
- Cleanup code is safety-critical.
- New cleanup behavior must have tests for allowed paths, protected paths, and dry-run behavior.
- Prefer environment variables for credentials.
- Do not document command examples that encourage token leakage into shell history.
- Use `swift build`, `swift test`, and `Scripts/enforce-local.sh` before opening a PR.
- Public API changes should follow Swift API Design Guidelines and include documentation comments.
- Keep the managed-worker direction unified for users; do not create new public repositories until an internal boundary has a second concrete consumer.

## Review Focus

Every substantive change should be reviewed for:
- filesystem deletion blast radius
- process matching and signal safety
- credential handling
- idempotence of setup/start/stop/remove operations
- test coverage for failure paths
- compatibility with self-hosted macOS runners
- whether a change belongs in runner lifecycle, capability discovery, host readiness, or host provisioning
