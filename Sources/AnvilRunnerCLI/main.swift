import Foundation
import AnvilRunner

@main
struct AnvilRunnerCLI {
    static func main() async {
        let arguments = CommandLine.arguments
        guard arguments.count > 1 else {
            printUsage()
            return
        }

        let command = arguments[1]

        do {
            switch command {
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

    private static func printUsage() {
        print("""
        anvil-runner — Self-hosted GitHub Actions runner manager for macOS

        USAGE:
          anvil-runner <command> [options]

        COMMANDS:
          setup       Install and configure runner instances
          start       Start runner instances
          stop        Stop runner instances
          remove      Remove runner instances and their directories
          status      Show runner health and system status
          clean       Clean workspace and build artifacts
          discover    Discover host capabilities (read-only)
          doctor      Check host health (read-only)
          help        Show this help message

        SETUP OPTIONS:
          --repo, -r <url>       GitHub repository URL
          --token, -t <token>    GitHub personal access token (prefer ANVIL_RUNNER_TOKEN env var)
          --count, -c <n>        Number of runner instances (default: 1)
          --name, -n <prefix>    Runner name prefix (default: macmini)
          --dir, -d <path>       Install directory (default: ~/actions-runner)
          --no-ephemeral         Disable ephemeral mode (persist between jobs)
          --aggressive           Use aggressive cleanup policy

        REMOVE OPTIONS:
          --token, -t <token>    GitHub runner removal token (prefer ANVIL_RUNNER_REMOVAL_TOKEN)
          --force-local          Delete local files without unregistering from GitHub

        STATUS OPTIONS:
          --count, -c <n>        Number of runners to check (default: 1)
          --name, -n <prefix>    Runner name prefix (default: macmini)

        DISCOVER/DOCTOR OPTIONS:
          --json                 Output JSON instead of human-readable text

        CLEAN OPTIONS:
          --workspace <path>     Clean specific workspace path
          --allow-root <path>    Additional root under which cleanup is allowed
          --dry-run              Print cleanup actions without deleting files
          --aggressive           Aggressive cleanup (all caches, derived data)

        EXAMPLES:
          ANVIL_RUNNER_TOKEN=<token> anvil-runner setup --repo https://github.com/your-org/your-repo --count 2
          anvil-runner start --count 2
          anvil-runner status --count 2
          anvil-runner clean --aggressive
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
}
