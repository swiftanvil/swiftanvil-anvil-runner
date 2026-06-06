import Foundation
import AnvilRunner

@main
struct AnvilRunnerCLI {
    static func main() async {
        let arguments = CommandLine.arguments
        let jsonMode = arguments.contains("--json")

        // Auto-build detection: if binary is missing, guide the agent
        let binaryPath = ProjectPaths.releaseBinary
        let fm = FileManager.default
        if !fm.fileExists(atPath: binaryPath) {
            if jsonMode {
                printJSON([
                    "error": "Binary not built",
                    "action_required": "Run 'swift build -c release' to build the project",
                    "current_state": "fresh-clone"
                ])
            } else {
                print("📦 Binary not built yet.")
                print("")
                print("To get started, run:")
                print("  swift build -c release")
                print("")
                print("Then re-run this command to see available actions.")
            }
            exit(1)
        }

        guard arguments.count > 1 else {
            // Agent-native mode: show current state and available actions
            await printAgentNativeState()
            return
        }

        let command = arguments[1]

        do {
            switch command {
            case "agent", "orchestrator":
                try await runAgentMode(arguments: Array(arguments.dropFirst(2)))
            case "setup":
                try await setupCommand(arguments: arguments)
            case "start":
                try await startCommand(arguments: arguments)
            case "stop":
                try await stopCommand(arguments: arguments)
            case "remove", "uninstall":
                try await removeCommand(arguments: arguments)
            case "status":
                try await statusCommand(arguments: arguments)
            case "clean", "cleanup":
                try await cleanCommand(arguments: arguments)
            case "discover":
                try await discoverCommand(arguments: arguments)
            case "doctor":
                try await doctorCommand(arguments: arguments)
            case "provision":
                try await provisionCommand(arguments: arguments)
            case "help", "--help", "-h":
                printUsage()
            default:
                print("Unknown command: \(command)")
                printUsage()
            }
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    }

    // MARK: - Agent-Native State Display

    private static func printAgentNativeState() async {
        let orchestrator = RunnerOrchestrator.shared
        let snapshot = await orchestrator.currentState()
        print(await orchestrator.whatCanIDo())
        print("")
        print("Run 'anvil-runner agent <action-id>' to execute an action.")
        print("Run 'anvil-runner help' for traditional CLI commands.")
    }

    // MARK: - Agent Mode

    private static func runAgentMode(arguments: [String]) async throws {
        let json = arguments.contains("--json")
        let cleanArgs = arguments.filter { $0 != "--json" }

        guard let actionID = cleanArgs.first else {
            await printAgentNativeState()
            return
        }

        let orchestrator = RunnerOrchestrator.shared
        let snapshot = await orchestrator.currentState()

        guard let action = snapshot.availableActions.first(where: { $0.id == actionID }) else {
            let result = RunnerActionResult(
                actionID: actionID,
                success: false,
                message: "Action '\(actionID)' is not available from state '\(snapshot.state.description)'. " +
                         "Available actions: \(snapshot.availableActions.map(\.id).joined(separator: ", "))"
            )
            if json {
                printJSON(result.toJSON())
            } else {
                print("❌ \(result.message)")
            }
            exit(1)
        }

        // Parse parameters from remaining args (--key value)
        var parameters: [String: String] = [:]
        var i = 1
        while i < cleanArgs.count {
            let arg = cleanArgs[i]
            if arg.hasPrefix("--"), i + 1 < cleanArgs.count {
                let key = String(arg.dropFirst(2))
                parameters[key] = cleanArgs[i + 1]
                i += 2
            } else {
                i += 1
            }
        }

        // Confirm destructive actions
        if action.requiresConfirmation && !json {
            print("⚠️  Action '\(action.name)' requires confirmation.")
            print("   \(action.description)")
            print("   Type 'yes' to proceed: ", terminator: "")
            guard let response = readLine()?.lowercased(), response == "yes" else {
                print("Cancelled.")
                exit(0)
            }
        }

        let result = await orchestrator.execute(actionID: actionID, parameters: parameters)

        if json {
            printJSON(result.toJSON())
        } else {
            if result.success {
                print("✅ \(result.message)")
            } else {
                print("❌ \(result.message)")
            }
            if !result.details.isEmpty {
                print("")
                for (key, value) in result.details {
                    print("  \(key): \(value)")
                }
            }
            if let newState = result.newState {
                print("")
                print("New state: \(newState.description)")
                let newSnapshot = await orchestrator.currentState()
                let nextActions = newSnapshot.availableActions
                if !nextActions.isEmpty {
                    print("Next available actions:")
                    for a in nextActions {
                        print("  • \(a.id) — \(a.name)")
                    }
                }
            }
        }

        exit(result.success ? 0 : 1)
    }

    // MARK: - Commands

    private static func setupCommand(arguments: [String]) async throws {
        let repo = extractOption(arguments, key: "--repo")
            ?? extractOption(arguments, key: "-r")
            ?? prompt("GitHub repository URL (e.g., https://github.com/your-org/your-repo): ")

        let token = extractOption(arguments, key: "--token")
            ?? extractOption(arguments, key: "-t")
            ?? ProcessInfo.processInfo.environment["ANVIL_RUNNER_TOKEN"]
            ?? ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
            ?? prompt("GitHub personal access token: ")

        let count = Int(extractOption(arguments, key: "--count")
            ?? extractOption(arguments, key: "-c")
            ?? "1") ?? 1

        let namePrefix = extractOption(arguments, key: "--name")
            ?? extractOption(arguments, key: "-n")
            ?? "macmini"

        let installDir = extractOption(arguments, key: "--dir")
            ?? extractOption(arguments, key: "-d")
            ?? "~/actions-runner"

        let ephemeral = !arguments.contains("--no-ephemeral")
        let aggressive = arguments.contains("--aggressive")

        let config = RunnerConfiguration(
            repositoryURL: repo,
            token: token,
            runnerCount: count,
            namePrefix: namePrefix,
            installDirectory: installDir,
            ephemeral: ephemeral,
            cleanupPolicy: aggressive ? .aggressive : .standard
        )

        print("Setting up \(count) runner(s) for \(repo)...")
        let lifecycle = RunnerLifecycle()
        try await lifecycle.setup(configuration: config)
        print("✅ Setup complete. Run 'anvil-runner start' to begin.")
    }

    private static func startCommand(arguments: [String]) async throws {
        let installDir = extractOption(arguments, key: "--dir")
            ?? extractOption(arguments, key: "-d")
            ?? "~/actions-runner"

        let count = Int(extractOption(arguments, key: "--count")
            ?? extractOption(arguments, key: "-c")
            ?? "1") ?? 1

        let namePrefix = extractOption(arguments, key: "--name")
            ?? extractOption(arguments, key: "-n")
            ?? "macmini"

        print("Starting \(count) runner(s)...")
        let lifecycle = RunnerLifecycle()
        try await lifecycle.start(
            installDirectory: (installDir as NSString).expandingTildeInPath,
            count: count,
            namePrefix: namePrefix
        )
        print("✅ Runners started.")
    }

    private static func stopCommand(arguments: [String]) async throws {
        let installDir = extractOption(arguments, key: "--dir")
            ?? extractOption(arguments, key: "-d")
            ?? "~/actions-runner"

        let count = Int(extractOption(arguments, key: "--count")
            ?? extractOption(arguments, key: "-c")
            ?? "1") ?? 1

        let namePrefix = extractOption(arguments, key: "--name")
            ?? extractOption(arguments, key: "-n")
            ?? "macmini"

        print("Stopping \(count) runner(s)...")
        let lifecycle = RunnerLifecycle()
        try await lifecycle.stop(
            installDirectory: (installDir as NSString).expandingTildeInPath,
            count: count,
            namePrefix: namePrefix
        )
        print("✅ Runners stopped.")
    }

    private static func removeCommand(arguments: [String]) async throws {
        let installDir = extractOption(arguments, key: "--dir")
            ?? extractOption(arguments, key: "-d")
            ?? "~/actions-runner"

        let count = Int(extractOption(arguments, key: "--count")
            ?? extractOption(arguments, key: "-c")
            ?? "1") ?? 1

        let namePrefix = extractOption(arguments, key: "--name")
            ?? extractOption(arguments, key: "-n")
            ?? "macmini"
        let expandedInstallDir = (installDir as NSString).expandingTildeInPath
        let forceLocal = arguments.contains("--force-local")
        let token = extractOption(arguments, key: "--token")
            ?? extractOption(arguments, key: "-t")
            ?? ProcessInfo.processInfo.environment["ANVIL_RUNNER_REMOVAL_TOKEN"]
            ?? ProcessInfo.processInfo.environment["ANVIL_RUNNER_TOKEN"]
            ?? ProcessInfo.processInfo.environment["GITHUB_TOKEN"]

        print("Removing \(count) runner(s)...")
        let defaultPolicy = CleanupSafetyPolicy.runnerDefault()
        let lifecycle = RunnerLifecycle(
            safetyPolicy: CleanupSafetyPolicy(
                allowedRootDirectories: defaultPolicy.allowedRootDirectories + [expandedInstallDir],
                protectedDirectories: defaultPolicy.protectedDirectories
            )
        )
        try await lifecycle.remove(
            installDirectory: expandedInstallDir,
            count: count,
            namePrefix: namePrefix,
            token: token,
            forceLocal: forceLocal
        )
        print("✅ Runners removed.")
    }

    private static func statusCommand(arguments: [String]) async throws {
        let installDir = extractOption(arguments, key: "--dir")
            ?? extractOption(arguments, key: "-d")
            ?? "~/actions-runner"

        let count = Int(extractOption(arguments, key: "--count")
            ?? extractOption(arguments, key: "-c")
            ?? "1") ?? 1

        let namePrefix = extractOption(arguments, key: "--name")
            ?? extractOption(arguments, key: "-n")
            ?? "macmini"

        let monitor = HealthMonitor()
        let statuses = await monitor.checkFleet(
            installDirectory: (installDir as NSString).expandingTildeInPath,
            count: count,
            namePrefix: namePrefix
        )

        let report = await monitor.formatReport(statuses)
        print(report)

        // Alert if critical
        if await monitor.isDiskCritical() {
            print("\n⚠️  WARNING: Disk usage is critical. Run 'anvil-runner clean' to free space.")
        }
    }

    private static func cleanCommand(arguments: [String]) async throws {
        let aggressive = arguments.contains("--aggressive")
        let dryRun = arguments.contains("--dry-run")
        let workspace = extractOption(arguments, key: "--workspace")
        let allowedRoot = extractOption(arguments, key: "--allow-root")

        let defaultPolicy = CleanupSafetyPolicy.runnerDefault(dryRun: dryRun)
        var allowedRootDirectories = defaultPolicy.allowedRootDirectories
        if let allowedRoot {
            let expandedRoot = (allowedRoot as NSString).expandingTildeInPath
            guard defaultPolicy.allowsAdditionalRoot(expandedRoot) else {
                throw CleanupError.unsafePath(expandedRoot)
            }
            allowedRootDirectories.append(expandedRoot)
        }
        let executor = CleanupExecutor(
            safetyPolicy: CleanupSafetyPolicy(
                allowedRootDirectories: allowedRootDirectories,
                protectedDirectories: defaultPolicy.protectedDirectories,
                dryRun: dryRun
            )
        )

        if let workspace = workspace {
            print("Cleaning workspace: \(workspace)...")
            let result = try await executor.execute(
                policy: aggressive ? .aggressive : .standard,
                workspacePath: workspace
            )
            printCleanupResult(result)
        } else {
            print("Running scheduled deep clean...")
            let result = try await executor.scheduledDeepClean(daysOld: aggressive ? 1 : 7)
            printCleanupResult(result)
        }

        if dryRun {
            print("✅ Cleanup dry run complete.")
        } else {
            let diskUsage = try await executor.diskUsagePercent()
            print("✅ Cleanup complete. Disk usage: \(diskUsage)%")
        }
    }

    // MARK: - Helpers

    private static func discoverCommand(arguments: [String]) async throws {
        let json = arguments.contains("--json")
        let discovery = CapabilityDiscovery()
        let report = await discovery.discover()

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print(report.formattedDiscovery())
        }
    }

    private static func doctorCommand(arguments: [String]) async throws {
        let json = arguments.contains("--json")
        let discovery = CapabilityDiscovery()
        let report = await discovery.doctor()

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print(report.formattedDoctor())
        }

        let hasFailures = report.checks.contains { $0.status == CheckStatus.fail }
        if hasFailures {
            exit(1)
        }
    }

    private static func provisionCommand(arguments: [String]) async throws {
        let profileName = extractOption(arguments, key: "--profile")
            ?? extractOption(arguments, key: "-p")
            ?? "build-worker"
        let dryRun = !arguments.contains("--apply")
        let autoConfirm = arguments.contains("--yes")

        let profile: WorkerProfile
        if let builtIn = WorkerProfile.allBuiltIn.first(where: { $0.name == profileName }) {
            profile = builtIn
        } else {
            print("Unknown profile: \(profileName)")
            print("Built-in profiles: \(WorkerProfile.allBuiltIn.map(\.name).joined(separator: ", "))")
            exit(1)
        }

        let planner = ProvisioningPlanner()
        let plan = await planner.plan(for: profile)

        let executor = ProvisioningExecutor()
        let result = await executor.apply(plan: plan, dryRun: dryRun, autoConfirm: autoConfirm)

        if !result.appliedChanges.isEmpty {
            print("\n✅ Applied \(result.appliedChanges.count) change(s).")
        }
        if !result.skippedChanges.isEmpty && dryRun {
            print("\n📝 Skipped \(result.skippedChanges.count) change(s) (dry run).")
        }
        if !result.errors.isEmpty {
            print("\n❌ Errors:")
            for error in result.errors {
                print("  \(error.changeID): \(error.message)")
            }
            exit(1)
        }
    }

    private static func printUsage() {
        print("""
        anvil-runner — AI-native self-hosted GitHub Actions runner manager for macOS

        AGENT-NATIVE MODE (default):
          anvil-runner                    Show current state and available actions
          anvil-runner agent <action>     Execute an action by ID

        ACTIONS:
          agent build                     Build the project
          agent doctor                    Run health checks
          agent discover                  Discover host capabilities
          agent setup                     Set up runners for a repo (requires --repo and --token)
          agent start                     Start configured runners
          agent stop                      Stop running runners
          agent remove                    Remove runners (requires --token)
          agent status                    Check runner health
          agent clean                     Clean workspace and artifacts
          agent provision-worker          Apply a worker profile

        TRADITIONAL COMMANDS:
          setup       Install and configure runner instances
          start       Start runner instances
          stop        Stop runner instances
          remove      Remove runner instances and their directories
          status      Show runner health and system status
          clean       Clean workspace and build artifacts
          discover    Discover host capabilities (read-only)
          doctor      Check host health (read-only)
          provision   Plan or apply worker provisioning (dry-run by default)
          help        Show this help message

        OPTIONS:
          --json                          Output machine-readable JSON
        """)
    }

    private static func extractOption(_ arguments: [String], key: String) -> String? {
        guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func prompt(_ message: String) -> String {
        print(message, terminator: " ")
        return readLine() ?? ""
    }

    private static func printCleanupResult(_ result: CleanupResult) {
        for path in result.dryRunPaths {
            print("Dry run: would remove \(path)")
        }
        for path in result.removedPaths {
            print("Removed \(path)")
        }
    }

    private static func printJSON(_ object: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            print("{\"error\": \"failed to serialize JSON\"}")
            return
        }
        print(string)
    }
}
