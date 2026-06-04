import Foundation

/// Manages the lifecycle of self-hosted GitHub Actions runners on macOS.
public actor RunnerLifecycle {
    private let fileManager = FileManager.default
    private let runnerVersion: String
    private let runnerDownloadURL: String
    private let safetyPolicy: CleanupSafetyPolicy

    public init(
        runnerVersion: String = "2.334.0",
        safetyPolicy: CleanupSafetyPolicy = .runnerDefault()
    ) {
        self.runnerVersion = runnerVersion
        self.safetyPolicy = safetyPolicy
        let arch = Self.detectArchitecture()
        self.runnerDownloadURL =
            "https://github.com/actions/runner/releases/download/v\(runnerVersion)/" +
            "actions-runner-osx-\(arch)-\(runnerVersion).tar.gz"
    }

    // MARK: - Setup

    /// Downloads, configures, and installs runner instances.
    public func setup(configuration: RunnerConfiguration) async throws {
        let installDir = configuration.installDirectory

        // Create install directory if needed
        if !fileManager.fileExists(atPath: installDir) {
            try fileManager.createDirectory(
                atPath: installDir,
                withIntermediateDirectories: true
            )
        }

        // Download runner archive once
        let archivePath = "\(installDir)/actions-runner.tar.gz"
        if !fileManager.fileExists(atPath: archivePath) {
            try await downloadRunner(to: archivePath)
        }

        // Configure each runner instance
        for i in 1...configuration.runnerCount {
            let runnerName = "\(configuration.namePrefix)-\(i)"
            let runnerDir = try Self.runnerDirectory(named: runnerName, under: installDir)

            try await installRunner(
                archivePath: archivePath,
                runnerDir: runnerDir,
                name: runnerName,
                configuration: configuration
            )
        }
    }

    /// Starts all configured runner instances as background services.
    public func start(installDirectory: String, count: Int, namePrefix: String) async throws {
        let installDirectory = CleanupSafetyPolicy.standardizedPath(installDirectory)
        for i in 1...max(1, count) {
            let runnerName = "\(namePrefix)-\(i)"
            let runnerDir = try Self.runnerDirectory(named: runnerName, under: installDirectory)
            try startRunner(in: runnerDir)
        }
    }

    /// Stops all running runner instances.
    public func stop(installDirectory: String, count: Int, namePrefix: String) async throws {
        let installDirectory = CleanupSafetyPolicy.standardizedPath(installDirectory)
        for i in 1...max(1, count) {
            let runnerName = "\(namePrefix)-\(i)"
            let runnerDir = try Self.runnerDirectory(named: runnerName, under: installDirectory)
            try await terminateRunner(named: runnerName, in: runnerDir)
        }
    }

    /// Unregisters and removes all runner instances and their directories.
    public func remove(
        installDirectory: String,
        count: Int,
        namePrefix: String,
        token: String? = nil,
        forceLocal: Bool = false
    ) async throws {
        let installDirectory = CleanupSafetyPolicy.standardizedPath(installDirectory)
        for i in 1...max(1, count) {
            let runnerName = "\(namePrefix)-\(i)"
            let runnerDir = try Self.runnerDirectory(named: runnerName, under: installDirectory)
            if fileManager.fileExists(atPath: runnerDir) {
                guard safetyPolicy.allowsRemoval(of: runnerDir) else {
                    throw CleanupError.unsafePath(runnerDir)
                }
                if !forceLocal {
                    guard let token, !token.isEmpty else {
                        throw RunnerError.configurationFailed(
                            reason: "Removal token is required unless forceLocal is enabled."
                        )
                    }
                    try await removeRunnerConfiguration(in: runnerDir, token: token)
                }
                try fileManager.removeItem(atPath: runnerDir)
            }
        }
    }

    // MARK: - Private

    private func downloadRunner(to path: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-o", path, "-L", runnerDownloadURL]

        try await runProcess(process)
    }

    private func installRunner(
        archivePath: String,
        runnerDir: String,
        name: String,
        configuration: RunnerConfiguration
    ) async throws {
        // Extract archive
        if !fileManager.fileExists(atPath: runnerDir) {
            try fileManager.createDirectory(atPath: runnerDir, withIntermediateDirectories: true)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["xzf", archivePath, "-C", runnerDir]
        try await runProcess(process)

        // Configure runner
        let configProcess = Process()
        configProcess.executableURL = URL(fileURLWithPath: "\(runnerDir)/config.sh")
        var configArgs = [
            "--unattended",
            "--url", configuration.repositoryURL,
            "--name", name,
            "--labels", configuration.labels.joined(separator: ",")
        ]
        if configuration.ephemeral {
            configArgs.append("--ephemeral")
        }
        configProcess.arguments = configArgs
        configProcess.environment = Self.environment(addingRunnerToken: configuration.token)
        configProcess.currentDirectoryURL = URL(fileURLWithPath: runnerDir)
        try await runProcess(configProcess)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runnerDir)
    }

    private func startRunner(in runnerDir: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "\(runnerDir)/run.sh")
        process.currentDirectoryURL = URL(fileURLWithPath: runnerDir)
        if let nullDevice = FileHandle(forWritingAtPath: "/dev/null") {
            process.standardOutput = nullDevice
            process.standardError = nullDevice
        }
        try process.run()
    }

    private func terminateRunner(named runnerName: String, in runnerDir: String) async throws {
        let pids = try await runnerProcessIDs(named: runnerName, in: runnerDir)
        for pid in pids {
            try await terminateProcess(pid: pid)
        }
    }

    private func removeRunnerConfiguration(in runnerDir: String, token: String) async throws {
        let configPath = "\(runnerDir)/config.sh"
        guard fileManager.fileExists(atPath: configPath) else {
            throw RunnerError.configurationFailed(
                reason: "Runner configuration script is missing. Use forceLocal to delete only local files."
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: configPath)
        process.arguments = ["remove"]
        process.environment = Self.environment(addingRunnerToken: token)
        process.currentDirectoryURL = URL(fileURLWithPath: runnerDir)
        try await runProcess(process)
    }

    private func runnerProcessIDs(named runnerName: String, in runnerDir: String) async throws -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-fl", "Runner.Listener"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 1 {
            return []
        }

        guard process.terminationStatus == 0 else {
            throw RunnerError.processFailed(exitCode: process.terminationStatus)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return Self.runnerProcessIDs(from: output, runnerName: runnerName, runnerDirectory: runnerDir)
    }

    private func terminateProcess(pid: Int32) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = [String(pid)]
        try await runProcess(process)
    }

    private func runProcess(_ process: Process) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: RunnerError.processFailed(
                        exitCode: proc.terminationStatus
                    ))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func runnerProcessIDs(from processList: String, runnerName: String, runnerDirectory: String) -> [Int32] {
        let standardizedRunnerDirectory = URL(fileURLWithPath: runnerDirectory).standardizedFileURL.path
        return processList.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let pidText = parts.first,
                  let pid = Int32(pidText),
                  parts.count == 2 else {
                return nil
            }

            let command = String(parts[1])
            guard command.contains(runnerName),
                  Self.command(command, containsPathBoundaryFor: standardizedRunnerDirectory) ||
                  Self.command(command, containsPathBoundaryFor: runnerDirectory) else {
                return nil
            }

            return pid
        }
    }

    static func command(_ command: String, containsPathBoundaryFor path: String) -> Bool {
        command.contains(path + "/") || command.hasSuffix(path)
    }

    static func runnerDirectory(named runnerName: String, under installDirectory: String) throws -> String {
        guard isValidRunnerName(runnerName) else {
            throw RunnerError.invalidRunnerName(runnerName)
        }

        let installDirectory = CleanupSafetyPolicy.standardizedPath(installDirectory)
        let candidate = CleanupSafetyPolicy.standardizedPath("\(installDirectory)/\(runnerName)")
        guard candidate.hasPrefix(installDirectory + "/") else {
            throw RunnerError.invalidRunnerName(runnerName)
        }

        return candidate
    }

    static func isValidRunnerName(_ runnerName: String) -> Bool {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return !runnerName.isEmpty &&
            runnerName.rangeOfCharacter(from: allowedCharacters.inverted) == nil &&
            runnerName != "." &&
            runnerName != ".."
    }

    static func environment(addingRunnerToken token: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["ACTIONS_RUNNER_INPUT_TOKEN"] = token
        return environment
    }

    static func detectArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x64"
        #endif
    }
}

public enum RunnerError: Error {
    case processFailed(exitCode: Int32)
    case downloadFailed(URL: String)
    case configurationFailed(reason: String)
    case invalidRunnerName(String)
}
