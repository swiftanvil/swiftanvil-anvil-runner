import Foundation

/// Manages the lifecycle of self-hosted GitHub Actions runners on macOS.
public actor RunnerLifecycle {
    private let fileManager = FileManager.default
    private let runnerVersion = "2.332.1"
    private let runnerDownloadURL: String

    public init() {
        let arch = Self.detectArchitecture()
        self.runnerDownloadURL =
            "https://github.com/actions/runner/releases/download/v\(runnerVersion)/actions-runner-osx-\(arch)-\(runnerVersion).tar.gz"
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
            let runnerDir = "\(installDir)/\(runnerName)"

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
        for i in 1...count {
            let runnerName = "\(namePrefix)-\(i)"
            let runnerDir = "\(installDirectory)/\(runnerName)"
            try await executeShell(command: "cd \(runnerDir) && ./run.sh &", directory: runnerDir)
        }
    }

    /// Stops all running runner instances.
    public func stop(installDirectory: String, count: Int, namePrefix: String) async throws {
        for i in 1...count {
            let runnerName = "\(namePrefix)-\(i)"
            try await terminateProcess(matching: "actions.runner.*\(runnerName)")
        }
    }

    /// Removes all runner instances and their directories.
    public func remove(installDirectory: String, count: Int, namePrefix: String) async throws {
        for i in 1...count {
            let runnerName = "\(namePrefix)-\(i)"
            let runnerDir = "\(installDirectory)/\(runnerName)"
            if fileManager.fileExists(atPath: runnerDir) {
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
            "--url", configuration.repositoryURL,
            "--token", configuration.token,
            "--name", name,
            "--labels", configuration.labels.joined(separator: ",")
        ]
        if configuration.ephemeral {
            configArgs.append("--ephemeral")
        }
        configProcess.arguments = configArgs
        configProcess.currentDirectoryURL = URL(fileURLWithPath: runnerDir)
        try await runProcess(configProcess)
    }

    private func executeShell(command: String, directory: String? = nil) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        if let directory = directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }
        try await runProcess(process)
    }

    private func terminateProcess(matching pattern: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", pattern]
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

    private static func detectArchitecture() -> String {
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
}
