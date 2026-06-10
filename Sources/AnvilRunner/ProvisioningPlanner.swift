import Foundation

/// Generates provisioning plans by comparing a desired profile against the
/// current host state discovered by `CapabilityDiscovery`.
public actor ProvisioningPlanner {
    private let discovery: CapabilityDiscovery

    public init(discovery: CapabilityDiscovery = CapabilityDiscovery()) {
        self.discovery = discovery
    }

    /// Generates a provisioning plan for the given profile.
    /// The plan is always dry-run — no changes are made.
    public func plan(for profile: WorkerProfile) async -> ProvisioningPlan {
        let report = await discovery.discover()
        var changes: [PlannedChange] = []
        var guidance: [UserGuidance] = []

        // MARK: Toolchain checks

        if profile.requirements.requiresGitHubCLI, !report.capabilities.githubCLI.installed {
            guidance.append(UserGuidance(
                id: "install-gh-cli",
                category: "toolchain",
                message: "GitHub CLI is required but not installed. Install with: brew install gh",
                documentationURL: "https://cli.github.com/"
            ))
        }

        if let minSwift = profile.requirements.minSwiftVersion {
            let current = report.capabilities.swift.version ?? "0.0"
            if !versionSatisfies(current, minimum: minSwift) {
                guidance.append(UserGuidance(
                    id: "upgrade-swift",
                    category: "toolchain",
                    message: "Swift \(current) is below required \(minSwift). Upgrade via Xcode or swift.org.",
                    documentationURL: "https://swift.org/download/"
                ))
            }
        }

        if let minXcode = profile.requirements.minXcodeVersion {
            let current = report.capabilities.xcode.version ?? "0.0"
            if !versionSatisfies(current, minimum: minXcode) {
                guidance.append(UserGuidance(
                    id: "upgrade-xcode",
                    category: "toolchain",
                    message: "Xcode \(current) is below required \(minXcode). Upgrade via Mac App Store or developer portal.",
                    documentationURL: "https://developer.apple.com/download/"
                ))
            }
        }

        // MARK: Network checks

        if profile.networkSettings?.sshEnabled == true, !report.network.ssh.installed {
            guidance.append(UserGuidance(
                id: "enable-ssh",
                category: "network",
                message: "SSH is not installed. Enable Remote Login in System Settings > General > Sharing.",
                documentationURL: "https://support.apple.com/guide/mac-help/mchlp1066/mac"
            ))
        }

        if profile.networkSettings?.tailscaleEnabled == true, !report.network.tailscale.installed {
            guidance.append(UserGuidance(
                id: "install-tailscale",
                category: "network",
                message: "Tailscale is required but not installed. Download from tailscale.com or run: brew install tailscale",
                documentationURL: "https://tailscale.com/download/mac"
            ))
        }

        // MARK: Power checks

        if let power = profile.powerSettings {
            if power.preventSleep, !report.power.preventSleep {
                changes.append(PlannedChange(
                    id: "prevent-sleep",
                    category: "power",
                    description: "Prevent system sleep while on AC power",
                    command: "caffeinate -d &",
                    isPrivileged: false
                ))
            }

            if power.restartAfterPowerLoss {
                guidance.append(UserGuidance(
                    id: "restart-after-power-loss",
                    category: "power",
                    message: "Enable 'Start up automatically after a power failure' in System Settings > Energy.",
                    documentationURL: "https://support.apple.com/guide/mac-help/mchlp2587/mac"
                ))
            }

            if power.wakeForNetworkAccess {
                guidance.append(UserGuidance(
                    id: "wake-for-network",
                    category: "power",
                    message: "Enable 'Wake for network access' in System Settings > Energy.",
                    documentationURL: "https://support.apple.com/guide/mac-help/mchlp2587/mac"
                ))
            }
        }

        // MARK: Disk / Memory checks

        if let minDisk = profile.requirements.minFreeDiskGB {
            guidance.append(UserGuidance(
                id: "disk-check",
                category: "resources",
                message: "Ensure at least \(minDisk) GB of free disk space is available."
            ))
        }

        if let minMemory = profile.requirements.minMemoryGB {
            guidance.append(UserGuidance(
                id: "memory-check",
                category: "resources",
                message: "Ensure at least \(minMemory) GB of RAM is installed."
            ))
        }

        return ProvisioningPlan(
            profileName: profile.name,
            changes: changes,
            guidance: guidance
        )
    }

    // MARK: - Version Comparison

    /// Returns true if `current` is >= `minimum` (simple semver comparison).
    private func versionSatisfies(_ current: String, minimum: String) -> Bool {
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let minimumParts = minimum.split(separator: ".").compactMap { Int($0) }
        let maxLength = max(currentParts.count, minimumParts.count)
        for i in 0 ..< maxLength {
            let c = i < currentParts.count ? currentParts[i] : 0
            let m = i < minimumParts.count ? minimumParts[i] : 0
            if c > m { return true }
            if c < m { return false }
        }
        return true
    }
}
