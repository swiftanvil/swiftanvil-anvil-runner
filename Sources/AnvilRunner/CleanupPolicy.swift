import Foundation

/// Describes whether a cleanup action was performed or skipped.
public struct CleanupResult: Sendable, Equatable {
    /// Paths that were removed.
    public let removedPaths: [String]
    /// Paths that would have been removed if dry-run mode were disabled.
    public let dryRunPaths: [String]

    public init(removedPaths: [String] = [], dryRunPaths: [String] = []) {
        self.removedPaths = removedPaths
        self.dryRunPaths = dryRunPaths
    }

    /// A result with no cleanup actions.
    public static let empty = CleanupResult()

    fileprivate func appending(_ other: CleanupResult) -> CleanupResult {
        CleanupResult(
            removedPaths: removedPaths + other.removedPaths,
            dryRunPaths: dryRunPaths + other.dryRunPaths
        )
    }
}

/// Restricts cleanup to known-safe directories.
public struct CleanupSafetyPolicy: Sendable {
    /// Root directories under which removal is allowed.
    public let allowedRootDirectories: [String]
    /// Directories that must never be removed directly.
    public let protectedDirectories: [String]
    /// Whether cleanup should report actions without deleting files.
    public let dryRun: Bool

    public init(
        allowedRootDirectories: [String],
        protectedDirectories: [String] = [],
        dryRun: Bool = false
    ) {
        self.allowedRootDirectories = allowedRootDirectories.map(Self.standardizedPath)
        self.protectedDirectories = protectedDirectories.map(Self.standardizedPath)
        self.dryRun = dryRun
    }

    /// Returns a conservative default policy for runner workspaces and Swift build caches.
    public static func runnerDefault(
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        temporaryDirectory: String = NSTemporaryDirectory(),
        dryRun: Bool = false
    ) -> CleanupSafetyPolicy {
        let home = standardizedPath(homeDirectory)
        return CleanupSafetyPolicy(
            allowedRootDirectories: [
                "\(home)/actions-runner",
                "\(home)/.build",
                "\(home)/Library/Developer/Xcode/DerivedData",
                "\(home)/.swiftpm/cache",
                standardizedPath(temporaryDirectory)
            ],
            protectedDirectories: [
                "/",
                "/Applications",
                "/Library",
                "/System",
                "/Users",
                "/private",
                home,
                "\(home)/Library",
                "\(home)/Library/Developer",
                standardizedPath(temporaryDirectory)
            ],
            dryRun: dryRun
        )
    }

    func allowsRemoval(of path: String) -> Bool {
        let candidate = Self.standardizedPath(path)

        guard !protectedDirectories.contains(candidate) else {
            return false
        }

        guard let allowedRoot = allowedRootDirectories.first(where: { root in
            candidate == root || candidate.hasPrefix(root + "/")
        }) else {
            return false
        }

        guard !Self.isAllowedRootTooBroad(allowedRoot, protectedDirectories: protectedDirectories) else {
            return false
        }

        return !protectedDirectories.contains { protectedDirectory in
            guard protectedDirectory != "/",
                  protectedDirectory.count > allowedRoot.count else {
                return false
            }

            return candidate == protectedDirectory ||
                candidate.hasPrefix(protectedDirectory + "/")
        }
    }

    /// Returns true when the path is narrow enough to be added as an extra cleanup root.
    public func allowsAdditionalRoot(_ path: String) -> Bool {
        let root = Self.standardizedPath(path)
        return !protectedDirectories.contains(root) &&
            !Self.isAllowedRootTooBroad(root, protectedDirectories: protectedDirectories)
    }

    static func standardizedPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    static func isAllowedRootTooBroad(
        _ allowedRoot: String,
        protectedDirectories: [String]
    ) -> Bool {
        guard allowedRoot != "/" else { return true }
        return protectedDirectories.contains { protectedDirectory in
            protectedDirectory.hasPrefix(allowedRoot + "/")
        }
    }
}

/// Errors raised when cleanup would leave the configured safe area.
public enum CleanupError: Error, Equatable {
    case unsafePath(String)
}

/// Executes cleanup strategies for self-hosted runner workspaces.
public actor CleanupExecutor {
    private let fileManager = FileManager.default
    private let safetyPolicy: CleanupSafetyPolicy

    public init(safetyPolicy: CleanupSafetyPolicy = .runnerDefault()) {
        self.safetyPolicy = safetyPolicy
    }

    /// Performs cleanup based on the specified policy.
    @discardableResult
    public func execute(policy: CleanupPolicy, workspacePath: String) async throws -> CleanupResult {
        switch policy {
        case .minimal:
            return try await cleanupMinimal(workspacePath: workspacePath)
        case .standard:
            return try await cleanupStandard(workspacePath: workspacePath)
        case .aggressive:
            return try await cleanupAggressive(workspacePath: workspacePath)
        case .ephemeral:
            return try await cleanupEphemeral(workspacePath: workspacePath)
        }
    }

    /// Scheduled deep cleanup — removes artifacts older than specified days.
    @discardableResult
    public func scheduledDeepClean(daysOld: Int = 7) async throws -> CleanupResult {
        let home = fileManager.homeDirectoryForCurrentUser.path
        var result = CleanupResult.empty

        let pathsToClean = [
            "\(home)/.build/debug",
            "\(home)/.build/release",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/.swiftpm/cache"
        ]

        for path in pathsToClean {
            let pathResult = try await removeFilesOlderThan(days: daysOld, in: path)
            result = result.appending(pathResult)
        }

        // Clean runner work directories
        let actionsRunnerPath = "\(home)/actions-runner"
        if fileManager.fileExists(atPath: actionsRunnerPath) {
            let contents = try fileManager.contentsOfDirectory(atPath: actionsRunnerPath)
            for item in contents where item.starts(with: "_work") {
                let fullPath = "\(actionsRunnerPath)/\(item)"
                let pathResult = try await removeFilesOlderThan(days: daysOld, in: fullPath)
                result = result.appending(pathResult)
            }
        }

        return result
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

    private func cleanupMinimal(workspacePath: String) async throws -> CleanupResult {
        try removeItemIfAllowed(atPath: workspacePath)
    }

    private func cleanupStandard(workspacePath: String) async throws -> CleanupResult {
        let minimal = try await cleanupMinimal(workspacePath: workspacePath)
        let deepClean = try await scheduledDeepClean(daysOld: 7)
        return minimal.appending(deepClean)
    }

    private func cleanupAggressive(workspacePath: String) async throws -> CleanupResult {
        var result = try await cleanupMinimal(workspacePath: workspacePath)

        let home = fileManager.homeDirectoryForCurrentUser.path
        let paths = [
            "\(home)/.build",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/.swiftpm/cache"
        ]

        for path in paths {
            result = result.appending(try removeItemIfAllowed(atPath: path))
        }

        return result
    }

    private func cleanupEphemeral(workspacePath: String) async throws -> CleanupResult {
        // Full wipe of workspace and all build artifacts
        var result = try await cleanupMinimal(workspacePath: workspacePath)

        let home = fileManager.homeDirectoryForCurrentUser.path
        let buildPath = "\(home)/.build"
        result = result.appending(try removeItemIfAllowed(atPath: buildPath))

        // Only remove runner-owned temporary files. Never wipe the entire system temp directory.
        let tmpPath = NSTemporaryDirectory()
        let tmpContents = try fileManager.contentsOfDirectory(atPath: tmpPath)
        for item in tmpContents where Self.isRunnerTemporaryItem(item) {
            let fullPath = "\(tmpPath)/\(item)"
            result = result.appending(try removeItemIfAllowed(atPath: fullPath))
        }

        return result
    }

    private func removeFilesOlderThan(days: Int, in path: String) async throws -> CleanupResult {
        guard fileManager.fileExists(atPath: path) else { return .empty }

        let contents = try fileManager.contentsOfDirectory(atPath: path)
        let now = Date()
        let cutoff = now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        var result = CleanupResult.empty

        for item in contents {
            let fullPath = "\(path)/\(item)"
            guard let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                  let modDate = attrs[.modificationDate] as? Date else {
                continue
            }

            if modDate < cutoff {
                result = result.appending(try removeItemIfAllowed(atPath: fullPath))
            }
        }

        return result
    }

    private func removeItemIfAllowed(atPath path: String) throws -> CleanupResult {
        let standardized = CleanupSafetyPolicy.standardizedPath(path)
        guard fileManager.fileExists(atPath: standardized) else { return .empty }
        guard safetyPolicy.allowsRemoval(of: standardized) else {
            throw CleanupError.unsafePath(standardized)
        }

        if safetyPolicy.dryRun {
            return CleanupResult(dryRunPaths: [standardized])
        }

        try fileManager.removeItem(atPath: standardized)
        return CleanupResult(removedPaths: [standardized])
    }

    static func isRunnerTemporaryItem(_ item: String) -> Bool {
        item.hasPrefix("anvil-runner-") ||
            item.hasPrefix("swiftanvil-runner-") ||
            item.hasPrefix("actions-runner-")
    }
}
