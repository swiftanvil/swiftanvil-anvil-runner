import Foundation

/// High-level orchestrator that executes runner actions safely.
/// Designed for AI agent consumption — no CLI knowledge required.
public actor RunnerOrchestrator {
    public static let shared = RunnerOrchestrator()

    private let detector = RunnerStateDetector.shared
    private let discovery = RunnerActionDiscovery.shared

    private init() { }

    // MARK: - State & Discovery

    /// Returns the current state with all available actions.
    public func currentState(installDirectory: String? = nil) async -> RunnerStateSnapshot {
        let state = await detector.detect(installDirectory: installDirectory)
        let actions = discovery.availableActions(from: state)
        return RunnerStateSnapshot(state: state, availableActions: actions)
    }

    /// Returns a human-readable summary of what's possible right now.
    public func whatCanIDo(installDirectory: String? = nil) async -> String {
        let snapshot = await currentState(installDirectory: installDirectory)
        var lines: [String] = []

        lines.append("📍 Current State: \(snapshot.state.description)")
        lines.append("")
        lines.append("Available Actions:")

        for action in snapshot.availableActions {
            let confirm = action.requiresConfirmation ? " ⚠️" : ""
            let token = action.requiresToken ? " 🔑" : ""
            lines.append("  • \(action.name)\(confirm)\(token)")
            lines.append("    \(action.description)")
            if !action.parameters.isEmpty {
                for param in action.parameters {
                    let req = param.required ? " (required)" : " (optional)"
                    let def = param.defaultValue != nil ? ", default: \(param.defaultValue!)" : ""
                    lines.append("      --\(param.name): \(param.description)\(req)\(def)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Safe Execution

    /// Executes an action by ID, returning a structured result.
    /// This is the primary agent interface — no shell commands needed.
    public func execute(
        actionID: String,
        parameters: [String: String] = [:],
        installDirectory: String? = nil
    ) async -> RunnerActionResult {
        guard let action = discovery.action(id: actionID) else {
            return RunnerActionResult(
                actionID: actionID,
                success: false,
                message: "Unknown action: \(actionID)"
            )
        }

        let current = await detector.detect(installDirectory: installDirectory)
        guard action.availableFromStates.contains(current) else {
            return RunnerActionResult(
                actionID: actionID,
                success: false,
                message: "Action '\(action.name)' is not available from state '\(current.description)'. " +
                    "Available from: \(action.availableFromStates.map(\.description).joined(separator: ", "))"
            )
        }

        do {
            return try await executeAction(action, parameters: parameters, installDirectory: installDirectory)
        } catch {
            return RunnerActionResult(
                actionID: actionID,
                success: false,
                message: "Execution failed: \(error.localizedDescription)"
            )
        }
    }

    /// Executes an action with automatic state re-detection afterward.
    private func executeAction(
        _ action: RunnerAction,
        parameters: [String: String],
        installDirectory _: String?
    ) async throws -> RunnerActionResult {
        switch action.id {
        case "build":
            try await executeBuild()
        case "doctor":
            try await executeDoctor()
        case "discover":
            try await executeDiscover()
        case "setup":
            try await executeSetup(parameters: parameters)
        case "start":
            try await executeStart(parameters: parameters)
        case "stop":
            try await executeStop(parameters: parameters)
        case "remove":
            try await executeRemove(parameters: parameters)
        case "status":
            try await executeStatus(parameters: parameters)
        case "clean":
            try await executeClean(parameters: parameters)
        case "provision-worker":
            try await executeProvisionWorker(parameters: parameters)
        default:
            RunnerActionResult(
                actionID: action.id,
                success: false,
                message: "Action '\(action.id)' is defined but not yet implemented"
            )
        }
    }

    // MARK: - Action Implementations

    private func executeBuild() async throws -> RunnerActionResult {
        let (out, err, status) = shell("/usr/bin/swift", ["build", "-c", "release"])
        let success = status == 0
        return RunnerActionResult(
            actionID: "build",
            success: success,
            message: success ? "Build completed successfully" : "Build failed: \(err)",
            details: ["stdout": out, "stderr": err],
            newState: success ? .built : nil
        )
    }

    private func executeDoctor() async throws -> RunnerActionResult {
        let discovery = CapabilityDiscovery()
        let report = await discovery.doctor()

        let hasFailures = report.checks.contains { $0.status == .fail }
        var details: [String: String] = [:]
        for check in report.checks {
            let symbol = check.status == .pass ? "✓" : (check.status == .warn ? "⚠️" : "✗")
            details[check.id] = "\(symbol) \(check.message)"
        }

        return RunnerActionResult(
            actionID: "doctor",
            success: !hasFailures,
            message: hasFailures ? "Some health checks failed" : "All health checks passed",
            details: details
        )
    }

    private func executeDiscover() async throws -> RunnerActionResult {
        let discovery = CapabilityDiscovery()
        let report = await discovery.discover()

        let details: [String: String] = [
            "host": "\(report.host.hostname) (macOS \(report.host.platformVersion), \(report.host.architecture))",
            "swift": report.capabilities.swift
                .installed ? (report.capabilities.swift.version ?? "installed") : "not found",
            "xcode": report.capabilities.xcode
                .installed ? (report.capabilities.xcode.version ?? "installed") : "not found",
            "git": report.capabilities.git.installed ? (report.capabilities.git.version ?? "installed") : "not found",
            "github_cli": report.capabilities.githubCLI
                .installed ? (report.capabilities.githubCLI.version ?? "installed") : "not found",
            "claude": report.agents.claude.installed ? "✓" : "✗",
            "codex": report.agents.codex.installed ? "✓" : "✗",
            "gemini": report.agents.gemini.installed ? "✓" : "✗",
            "ssh": report.network.ssh.installed ? "✓" : "✗",
            "tailscale": report.network.tailscale.installed ? "✓" : "✗",
            "ac_power": report.power.onACPower ? "✓" : "✗",
            "sleep_prevented": report.power.preventSleep ? "✓" : "✗"
        ]

        return RunnerActionResult(
            actionID: "discover",
            success: true,
            message: "Host capability discovery complete",
            details: details
        )
    }

    private func executeSetup(parameters: [String: String]) async throws -> RunnerActionResult {
        guard let repo = parameters["repo"] else {
            return RunnerActionResult(
                actionID: "setup",
                success: false,
                message: "Missing required parameter: repo (GitHub repository URL)"
            )
        }

        guard let token = parameters["token"] ?? ProcessInfo.processInfo.environment["ANVIL_RUNNER_TOKEN"] else {
            return RunnerActionResult(
                actionID: "setup",
                success: false,
                message: "Missing required parameter: token. Provide it as a parameter or set ANVIL_RUNNER_TOKEN environment variable."
            )
        }

        let count = Int(parameters["count"] ?? "2") ?? 2
        let namePrefix = parameters["name-prefix"] ?? "macmini"
        let installDir = parameters["install-dir"] ?? "~/actions-runner"

        let config = RunnerConfiguration(
            repositoryURL: repo,
            token: token,
            runnerCount: count,
            namePrefix: namePrefix,
            installDirectory: installDir
        )

        let lifecycle = RunnerLifecycle()
        try await lifecycle.setup(configuration: config)

        return RunnerActionResult(
            actionID: "setup",
            success: true,
            message: "\(count) runner(s) configured for \(repo)",
            details: [
                "repo": repo,
                "count": String(count),
                "name_prefix": namePrefix,
                "install_dir": installDir
            ],
            newState: .configured
        )
    }

    private func executeStart(parameters: [String: String]) async throws -> RunnerActionResult {
        let count = Int(parameters["count"] ?? "2") ?? 2
        let namePrefix = parameters["name-prefix"] ?? "macmini"
        let installDir = ((parameters["install-dir"] ?? "~/actions-runner") as NSString).expandingTildeInPath

        let lifecycle = RunnerLifecycle()
        try await lifecycle.start(installDirectory: installDir, count: count, namePrefix: namePrefix)

        return RunnerActionResult(
            actionID: "start",
            success: true,
            message: "\(count) runner(s) started",
            details: [
                "count": String(count),
                "name_prefix": namePrefix
            ],
            newState: .running
        )
    }

    private func executeStop(parameters: [String: String]) async throws -> RunnerActionResult {
        let count = Int(parameters["count"] ?? "2") ?? 2
        let namePrefix = parameters["name-prefix"] ?? "macmini"
        let installDir = ((parameters["install-dir"] ?? "~/actions-runner") as NSString).expandingTildeInPath

        let lifecycle = RunnerLifecycle()
        try await lifecycle.stop(installDirectory: installDir, count: count, namePrefix: namePrefix)

        return RunnerActionResult(
            actionID: "stop",
            success: true,
            message: "\(count) runner(s) stopped",
            details: [
                "count": String(count),
                "name_prefix": namePrefix
            ],
            newState: .stopped
        )
    }

    private func executeRemove(parameters: [String: String]) async throws -> RunnerActionResult {
        let count = Int(parameters["count"] ?? "2") ?? 2
        let namePrefix = parameters["name-prefix"] ?? "macmini"
        let installDir = ((parameters["install-dir"] ?? "~/actions-runner") as NSString).expandingTildeInPath
        let forceLocal = parameters["force-local"]?.lowercased() == "true"

        let token = parameters["token"]
            ?? ProcessInfo.processInfo.environment["ANVIL_RUNNER_REMOVAL_TOKEN"]
            ?? ProcessInfo.processInfo.environment["ANVIL_RUNNER_TOKEN"]

        if !forceLocal, token == nil {
            return RunnerActionResult(
                actionID: "remove",
                success: false,
                message: "Removal token required. Provide token parameter, set ANVIL_RUNNER_REMOVAL_TOKEN, or use force-local=true"
            )
        }

        let lifecycle = RunnerLifecycle()
        try await lifecycle.remove(
            installDirectory: installDir,
            count: count,
            namePrefix: namePrefix,
            token: token,
            forceLocal: forceLocal
        )

        return RunnerActionResult(
            actionID: "remove",
            success: true,
            message: "\(count) runner(s) removed",
            details: [
                "count": String(count),
                "name_prefix": namePrefix,
                "force_local": String(forceLocal)
            ],
            newState: .built
        )
    }

    private func executeStatus(parameters: [String: String]) async throws -> RunnerActionResult {
        let count = Int(parameters["count"] ?? "2") ?? 2
        let namePrefix = parameters["name-prefix"] ?? "macmini"
        let installDir = ((parameters["install-dir"] ?? "~/actions-runner") as NSString).expandingTildeInPath

        let monitor = HealthMonitor()
        let statuses = await monitor.checkFleet(installDirectory: installDir, count: count, namePrefix: namePrefix)

        var details: [String: String] = [:]
        for status in statuses {
            let state = status.isRunning ? "🟢 Running" : "🔴 Stopped"
            details[status.name] = "\(state) | Disk: \(status.diskUsagePercent)% | Memory: \(status.memoryUsagePercent)%"
        }

        let anyRunning = statuses.contains(where: \.isRunning)
        let runningCount = statuses.count(where: { $0.isRunning })

        return RunnerActionResult(
            actionID: "status",
            success: true,
            message: "\(runningCount)/\(statuses.count) runners running",
            details: details,
            newState: anyRunning ? .running : .stopped
        )
    }

    private func executeClean(parameters: [String: String]) async throws -> RunnerActionResult {
        let aggressive = parameters["aggressive"]?.lowercased() == "true"
        let dryRun = parameters["dry-run"]?.lowercased() == "true"
        let workspace = parameters["workspace"]

        let executor = CleanupExecutor(
            safetyPolicy: CleanupSafetyPolicy(
                allowedRootDirectories: CleanupSafetyPolicy.runnerDefault().allowedRootDirectories,
                protectedDirectories: CleanupSafetyPolicy.runnerDefault().protectedDirectories,
                dryRun: dryRun
            )
        )

        let result: CleanupResult = if let workspace {
            try await executor.execute(
                policy: aggressive ? .aggressive : .standard,
                workspacePath: workspace
            )
        } else {
            try await executor.scheduledDeepClean(daysOld: aggressive ? 1 : 7)
        }

        var details: [String: String] = [:]
        if dryRun {
            details["dry_run_paths"] = result.dryRunPaths.joined(separator: ", ")
            details["would_remove_count"] = String(result.dryRunPaths.count)
        } else {
            details["removed_paths"] = result.removedPaths.joined(separator: ", ")
            details["removed_count"] = String(result.removedPaths.count)
            let diskUsage = try await executor.diskUsagePercent()
            details["disk_usage_after"] = "\(diskUsage)%"
        }

        return RunnerActionResult(
            actionID: "clean",
            success: true,
            message: dryRun ? "Dry run complete — \(result.dryRunPaths.count) items would be removed" :
                "Cleanup complete",
            details: details
        )
    }

    private func executeProvisionWorker(parameters: [String: String]) async throws -> RunnerActionResult {
        let profileName = parameters["profile"] ?? "build-worker"
        let apply = parameters["apply"]?.lowercased() == "true"
        let autoConfirm = parameters["yes"]?.lowercased() == "true"

        guard let profile = WorkerProfile.allBuiltIn.first(where: { $0.name == profileName }) else {
            return RunnerActionResult(
                actionID: "provision-worker",
                success: false,
                message: "Unknown profile: \(profileName). Built-in profiles: \(WorkerProfile.allBuiltIn.map(\.name).joined(separator: ", "))"
            )
        }

        let planner = ProvisioningPlanner()
        let plan = await planner.plan(for: profile)

        let executor = ProvisioningExecutor()
        let result = await executor.apply(plan: plan, dryRun: !apply, autoConfirm: autoConfirm)

        let details: [String: String] = [
            "profile": profileName,
            "dry_run": String(!apply),
            "applied_changes": String(result.appliedChanges.count),
            "skipped_changes": String(result.skippedChanges.count),
            "errors": String(result.errors.count)
        ]

        return RunnerActionResult(
            actionID: "provision-worker",
            success: result.errors.isEmpty,
            message: apply
                ? "Applied \(result.appliedChanges.count) change(s) with \(result.errors.count) error(s)"
                : "Dry run: \(result.skippedChanges.count) change(s) would be applied",
            details: details
        )
    }
}

// MARK: - State Snapshot

public struct RunnerStateSnapshot: Sendable {
    public let state: RunnerState
    public let availableActions: [RunnerAction]

    public func toJSON() -> [String: Any] {
        [
            "state": state.toJSON(),
            "available_actions": availableActions.map { $0.toJSON() }
        ]
    }
}

// MARK: - Shell Helper

private func shell(_ executable: String, _ args: [String]) -> (stdout: String, stderr: String, status: Int32) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = args

    let outPipe = Pipe()
    let errPipe = Pipe()
    task.standardOutput = outPipe
    task.standardError = errPipe

    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return ("", error.localizedDescription, -1)
    }

    let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (out, err, task.terminationStatus)
}
