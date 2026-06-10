import Foundation

// MARK: - Worker Profile

/// A named profile describing the desired state of a worker host.
public struct WorkerProfile: Codable, Sendable {
    public var name: String
    public var description: String
    public var role: WorkerRole
    public var requirements: ProfileRequirements
    public var powerSettings: PowerSettings?
    public var networkSettings: NetworkSettings?
    public var labels: [String]

    public init(
        name: String,
        description: String,
        role: WorkerRole,
        requirements: ProfileRequirements,
        powerSettings: PowerSettings? = nil,
        networkSettings: NetworkSettings? = nil,
        labels: [String] = []
    ) {
        self.name = name
        self.description = description
        self.role = role
        self.requirements = requirements
        self.powerSettings = powerSettings
        self.networkSettings = networkSettings
        self.labels = labels
    }
}

public enum WorkerRole: String, Codable, Sendable {
    case build
    case test
    case review
    case performance
}

// MARK: - Profile Requirements

public struct ProfileRequirements: Codable, Sendable {
    public var minSwiftVersion: String?
    public var minXcodeVersion: String?
    public var requiresGitHubCLI: Bool
    public var requiresSSH: Bool
    public var requiresTailscale: Bool
    public var minMemoryGB: Int?
    public var minFreeDiskGB: Int?

    public init(
        minSwiftVersion: String? = nil,
        minXcodeVersion: String? = nil,
        requiresGitHubCLI: Bool = false,
        requiresSSH: Bool = false,
        requiresTailscale: Bool = false,
        minMemoryGB: Int? = nil,
        minFreeDiskGB: Int? = nil
    ) {
        self.minSwiftVersion = minSwiftVersion
        self.minXcodeVersion = minXcodeVersion
        self.requiresGitHubCLI = requiresGitHubCLI
        self.requiresSSH = requiresSSH
        self.requiresTailscale = requiresTailscale
        self.minMemoryGB = minMemoryGB
        self.minFreeDiskGB = minFreeDiskGB
    }
}

// MARK: - Power Settings

public struct PowerSettings: Codable, Sendable {
    public var preventSleep: Bool
    public var restartAfterPowerLoss: Bool
    public var wakeForNetworkAccess: Bool

    public init(
        preventSleep: Bool = true,
        restartAfterPowerLoss: Bool = true,
        wakeForNetworkAccess: Bool = true
    ) {
        self.preventSleep = preventSleep
        self.restartAfterPowerLoss = restartAfterPowerLoss
        self.wakeForNetworkAccess = wakeForNetworkAccess
    }
}

// MARK: - Network Settings

public struct NetworkSettings: Codable, Sendable {
    public var sshEnabled: Bool
    public var tailscaleEnabled: Bool
    public var remoteLoginEnabled: Bool

    public init(
        sshEnabled: Bool = true,
        tailscaleEnabled: Bool = false,
        remoteLoginEnabled: Bool = true
    ) {
        self.sshEnabled = sshEnabled
        self.tailscaleEnabled = tailscaleEnabled
        self.remoteLoginEnabled = remoteLoginEnabled
    }
}

// MARK: - Provisioning Plan

/// A concrete, auditable plan of changes derived from a profile and current host state.
public struct ProvisioningPlan: Sendable {
    public var profileName: String
    public var changes: [PlannedChange]
    public var guidance: [UserGuidance]
    public var isNoOp: Bool {
        changes.isEmpty && guidance.isEmpty
    }

    public init(profileName: String, changes: [PlannedChange], guidance: [UserGuidance]) {
        self.profileName = profileName
        self.changes = changes
        self.guidance = guidance
    }
}

/// A single change that the provisioner can apply.
public struct PlannedChange: Sendable {
    public var id: String
    public var category: String
    public var description: String
    public var command: String?
    public var isPrivileged: Bool

    public init(
        id: String,
        category: String,
        description: String,
        command: String? = nil,
        isPrivileged: Bool = false
    ) {
        self.id = id
        self.category = category
        self.description = description
        self.command = command
        self.isPrivileged = isPrivileged
    }
}

/// Guidance for the user to perform manually.
public struct UserGuidance: Sendable {
    public var id: String
    public var category: String
    public var message: String
    public var documentationURL: String?

    public init(
        id: String,
        category: String,
        message: String,
        documentationURL: String? = nil
    ) {
        self.id = id
        self.category = category
        self.message = message
        self.documentationURL = documentationURL
    }
}

// MARK: - Provisioning Result

/// The outcome of applying a provisioning plan.
public struct ProvisioningResult: Sendable {
    public var appliedChanges: [String]
    public var skippedChanges: [String]
    public var errors: [ProvisioningError]
    public var auditLog: [AuditEntry]

    public init(
        appliedChanges: [String] = [],
        skippedChanges: [String] = [],
        errors: [ProvisioningError] = [],
        auditLog: [AuditEntry] = []
    ) {
        self.appliedChanges = appliedChanges
        self.skippedChanges = skippedChanges
        self.errors = errors
        self.auditLog = auditLog
    }
}

public struct AuditEntry: Sendable {
    public var timestamp: String
    public var changeID: String
    public var status: String

    public init(timestamp: String, changeID: String, status: String) {
        self.timestamp = timestamp
        self.changeID = changeID
        self.status = status
    }
}

public struct ProvisioningError: Error, Sendable {
    public var changeID: String
    public var message: String

    public init(changeID: String, message: String) {
        self.changeID = changeID
        self.message = message
    }
}

// MARK: - Built-in Profiles

public extension WorkerProfile {
    /// A standard build worker profile.
    static var buildWorker: WorkerProfile {
        WorkerProfile(
            name: "build-worker",
            description: "Standard CI build worker with Swift toolchain and GitHub CLI",
            role: .build,
            requirements: ProfileRequirements(
                minSwiftVersion: "6.0",
                requiresGitHubCLI: true,
                requiresSSH: true,
                minMemoryGB: 8,
                minFreeDiskGB: 50
            ),
            powerSettings: PowerSettings(
                preventSleep: true,
                restartAfterPowerLoss: true,
                wakeForNetworkAccess: true
            ),
            networkSettings: NetworkSettings(
                sshEnabled: true,
                tailscaleEnabled: false,
                remoteLoginEnabled: true
            ),
            labels: ["self-hosted", "macOS", "build"]
        )
    }

    /// A test worker profile with more disk space for simulators.
    static var testWorker: WorkerProfile {
        WorkerProfile(
            name: "test-worker",
            description: "CI test worker with Xcode simulators and larger disk allocation",
            role: .test,
            requirements: ProfileRequirements(
                minSwiftVersion: "6.0",
                minXcodeVersion: "16.0",
                requiresGitHubCLI: true,
                requiresSSH: true,
                minMemoryGB: 16,
                minFreeDiskGB: 100
            ),
            powerSettings: PowerSettings(
                preventSleep: true,
                restartAfterPowerLoss: true,
                wakeForNetworkAccess: true
            ),
            networkSettings: NetworkSettings(
                sshEnabled: true,
                tailscaleEnabled: false,
                remoteLoginEnabled: true
            ),
            labels: ["self-hosted", "macOS", "test"]
        )
    }

    /// A review worker profile for PR checks.
    static var reviewWorker: WorkerProfile {
        WorkerProfile(
            name: "review-worker",
            description: "Lightweight PR review worker",
            role: .review,
            requirements: ProfileRequirements(
                minSwiftVersion: "6.0",
                requiresGitHubCLI: true,
                requiresSSH: false,
                minMemoryGB: 8,
                minFreeDiskGB: 30
            ),
            powerSettings: PowerSettings(
                preventSleep: true,
                restartAfterPowerLoss: false,
                wakeForNetworkAccess: true
            ),
            networkSettings: NetworkSettings(
                sshEnabled: false,
                tailscaleEnabled: false,
                remoteLoginEnabled: true
            ),
            labels: ["self-hosted", "macOS", "review"]
        )
    }

    /// All built-in profiles.
    static var allBuiltIn: [WorkerProfile] {
        [buildWorker, testWorker, reviewWorker]
    }
}
