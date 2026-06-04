import Foundation

/// Configuration for a self-hosted GitHub Actions runner instance.
public struct RunnerConfiguration: Sendable {
    /// The GitHub repository URL (e.g., "https://github.com/v-i-s-h-a-l/iStudio").
    public let repositoryURL: String
    /// The GitHub personal access token for runner registration.
    public let token: String
    /// The number of runner instances to create on this machine.
    public let runnerCount: Int
    /// The name prefix for each runner instance (e.g., "macmini-1", "macmini-2").
    public let namePrefix: String
    /// The directory where runners will be installed.
    public let installDirectory: String
    /// Whether runners should be ephemeral (clean workspace after each job).
    public let ephemeral: Bool
    /// The cleanup policy applied after each job.
    public let cleanupPolicy: CleanupPolicy
    /// Memory limit guidance for build tools (in gigabytes).
    public let memoryLimitGB: Int
    /// Disk usage threshold for alerts (percentage, 0-100).
    public let diskAlertThreshold: Int
    /// Labels assigned to runners for workflow targeting.
    public let labels: [String]

    public init(
        repositoryURL: String,
        token: String,
        runnerCount: Int = 1,
        namePrefix: String = "macmini",
        installDirectory: String = "~/actions-runner",
        ephemeral: Bool = true,
        cleanupPolicy: CleanupPolicy = .standard,
        memoryLimitGB: Int = 8,
        diskAlertThreshold: Int = 80,
        labels: [String] = ["self-hosted", "macOS", "arm64"]
    ) {
        self.repositoryURL = repositoryURL
        self.token = token
        self.runnerCount = max(1, runnerCount)
        self.namePrefix = namePrefix
        self.installDirectory = (installDirectory as NSString).expandingTildeInPath
        self.ephemeral = ephemeral
        self.cleanupPolicy = cleanupPolicy
        self.memoryLimitGB = max(1, memoryLimitGB)
        self.diskAlertThreshold = min(100, max(0, diskAlertThreshold))
        self.labels = labels
    }
}

/// Defines how aggressively the runner cleans up after each job.
public enum CleanupPolicy: String, Sendable, CaseIterable {
    /// Minimal cleanup — only removes the checked-out repository workspace.
    case minimal
    /// Standard cleanup — workspace + build artifacts older than 7 days.
    case standard
    /// Aggressive cleanup — workspace + all caches + derived data.
    case aggressive
    /// Ephemeral mode — full wipe after every job (most isolated, slowest).
    case ephemeral
}

/// Represents the current status of a runner instance.
public struct RunnerStatus: Sendable {
    public let name: String
    public let isRunning: Bool
    public let lastJobCompletedAt: Date?
    public let diskUsagePercent: Int
    public let memoryUsagePercent: Int
}
