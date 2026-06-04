import Foundation

/// Executes cleanup strategies for self-hosted runner workspaces.
public actor CleanupExecutor {
    private let fileManager = FileManager.default

    public init() {}

    /// Performs cleanup based on the specified policy.
    public func execute(policy: CleanupPolicy, workspacePath: String) async throws {
        switch policy {
        case .minimal:
            try await cleanupMinimal(workspacePath: workspacePath)
        case .standard:
            try await cleanupStandard(workspacePath: workspacePath)
        case .aggressive:
            try await cleanupAggressive(workspacePath: workspacePath)
        case .ephemeral:
            try await cleanupEphemeral(workspacePath: workspacePath)
        }
    }

    /// Scheduled deep cleanup — removes artifacts older than specified days.
    public func scheduledDeepClean(daysOld: Int = 7) async throws {
        let home = fileManager.homeDirectoryForCurrentUser.path

        let pathsToClean = [
            "\(home)/.build/debug",
            "\(home)/.build/release",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/.swiftpm/cache",
            "\(home)/.docker"
        ]

        for path in pathsToClean {
            try await removeFilesOlderThan(days: daysOld, in: path)
        }

        // Clean runner work directories
        let actionsRunnerPath = "\(home)/actions-runner"
        if fileManager.fileExists(atPath: actionsRunnerPath) {
            let contents = try fileManager.contentsOfDirectory(atPath: actionsRunnerPath)
            for item in contents where item.starts(with: "_work") {
                let fullPath = "\(actionsRunnerPath)/\(item)"
                try await removeFilesOlderThan(days: daysOld, in: fullPath)
            }
        }
    }

    /// Checks disk usage and returns percentage used.
    public func diskUsagePercent() async throws -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/df")
        process.arguments = ["-h", "/"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return 0
        }

        // Parse df output: "Filesystem  Size  Used Avail Use% Mounted on"
        let lines = output.split(separator: "\n")
        guard lines.count >= 2 else { return 0 }

        let mainLine = String(lines[1])
        let components = mainLine.split(separator: " ").filter { !$0.isEmpty }
        guard components.count >= 5 else { return 0 }

        let usePercentStr = String(components[4]).replacingOccurrences(of: "%", with: "")
        return Int(usePercentStr) ?? 0
    }

    // MARK: - Private

    private func cleanupMinimal(workspacePath: String) async throws {
        if fileManager.fileExists(atPath: workspacePath) {
            try fileManager.removeItem(atPath: workspacePath)
        }
    }

    private func cleanupStandard(workspacePath: String) async throws {
        try await cleanupMinimal(workspacePath: workspacePath)
        try await scheduledDeepClean(daysOld: 7)
    }

    private func cleanupAggressive(workspacePath: String) async throws {
        try await cleanupMinimal(workspacePath: workspacePath)

        let home = fileManager.homeDirectoryForCurrentUser.path
        let paths = [
            "\(home)/.build",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/.swiftpm/cache"
        ]

        for path in paths {
            if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(atPath: path)
            }
        }
    }

    private func cleanupEphemeral(workspacePath: String) async throws {
        // Full wipe of workspace and all build artifacts
        try await cleanupMinimal(workspacePath: workspacePath)

        let home = fileManager.homeDirectoryForCurrentUser.path
        let buildPath = "\(home)/.build"
        if fileManager.fileExists(atPath: buildPath) {
            try fileManager.removeItem(atPath: buildPath)
        }

        // Also clean any temporary files
        let tmpPath = NSTemporaryDirectory()
        let tmpContents = try fileManager.contentsOfDirectory(atPath: tmpPath)
        for item in tmpContents {
            let fullPath = "\(tmpPath)/\(item)"
            try? fileManager.removeItem(atPath: fullPath)
        }
    }

    private func removeFilesOlderThan(days: Int, in path: String) async throws {
        guard fileManager.fileExists(atPath: path) else { return }

        let contents = try fileManager.contentsOfDirectory(atPath: path)
        let now = Date()
        let cutoff = now.addingTimeInterval(-Double(days) * 24 * 60 * 60)

        for item in contents {
            let fullPath = "\(path)/\(item)"
            guard let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                  let modDate = attrs[.modificationDate] as? Date else {
                continue
            }

            if modDate < cutoff {
                try? fileManager.removeItem(atPath: fullPath)
            }
        }
    }
}
