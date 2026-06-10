import Foundation

// MARK: - Top-Level Report

/// The complete capability report produced by `discover` and `doctor`.
public struct CapabilityReport: Codable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: String
    public var host: HostInfo
    public var capabilities: ToolCapabilities
    public var agents: AgentCapabilities
    public var network: NetworkCapabilities
    public var power: PowerCapabilities
    public var checks: [HealthCheck]

    public init(
        schemaVersion: Int = 1,
        generatedAt: String,
        host: HostInfo,
        capabilities: ToolCapabilities,
        agents: AgentCapabilities,
        network: NetworkCapabilities,
        power: PowerCapabilities,
        checks: [HealthCheck]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.host = host
        self.capabilities = capabilities
        self.agents = agents
        self.network = network
        self.power = power
        self.checks = checks
    }
}

// MARK: - Host Info

public struct HostInfo: Codable, Sendable {
    public var platform: String
    public var platformVersion: String
    public var architecture: String
    public var hostname: String

    public init(platform: String, platformVersion: String, architecture: String, hostname: String) {
        self.platform = platform
        self.platformVersion = platformVersion
        self.architecture = architecture
        self.hostname = hostname
    }
}

// MARK: - Tool Capabilities

public struct ToolCapabilities: Codable, Sendable {
    public var swift: ToolInfo
    public var xcode: ToolInfo
    public var git: ToolInfo
    public var githubCLI: ToolInfo

    public init(swift: ToolInfo, xcode: ToolInfo, git: ToolInfo, githubCLI: ToolInfo) {
        self.swift = swift
        self.xcode = xcode
        self.git = git
        self.githubCLI = githubCLI
    }
}

public struct ToolInfo: Codable, Sendable {
    public var installed: Bool
    public var version: String?
    public var path: String?
    public var authenticated: Bool?

    public init(installed: Bool, version: String? = nil, path: String? = nil, authenticated: Bool? = nil) {
        self.installed = installed
        self.version = version
        self.path = path
        self.authenticated = authenticated
    }
}

// MARK: - Agent Capabilities

public struct AgentCapabilities: Codable, Sendable {
    public var claude: ToolInfo
    public var codex: ToolInfo
    public var gemini: ToolInfo

    public init(claude: ToolInfo, codex: ToolInfo, gemini: ToolInfo) {
        self.claude = claude
        self.codex = codex
        self.gemini = gemini
    }
}

// MARK: - Network Capabilities

public struct NetworkCapabilities: Codable, Sendable {
    public var ssh: SSHInfo
    public var tailscale: TailscaleInfo

    public init(ssh: SSHInfo, tailscale: TailscaleInfo) {
        self.ssh = ssh
        self.tailscale = tailscale
    }
}

public struct SSHInfo: Codable, Sendable {
    public var installed: Bool
    public var reachable: Bool
    public var keyConfigured: Bool

    public init(installed: Bool, reachable: Bool, keyConfigured: Bool) {
        self.installed = installed
        self.reachable = reachable
        self.keyConfigured = keyConfigured
    }
}

public struct TailscaleInfo: Codable, Sendable {
    public var installed: Bool
    public var running: Bool
    public var loggedIn: Bool

    public init(installed: Bool, running: Bool, loggedIn: Bool) {
        self.installed = installed
        self.running = running
        self.loggedIn = loggedIn
    }
}

// MARK: - Power Capabilities

public struct PowerCapabilities: Codable, Sendable {
    public var preventSleep: Bool
    public var onACPower: Bool

    public init(preventSleep: Bool, onACPower: Bool) {
        self.preventSleep = preventSleep
        self.onACPower = onACPower
    }
}

// MARK: - Health Check

public struct HealthCheck: Codable, Sendable {
    public var id: String
    public var category: String
    public var status: CheckStatus
    public var message: String

    public init(id: String, category: String, status: CheckStatus, message: String) {
        self.id = id
        self.category = category
        self.status = status
        self.message = message
    }
}

public enum CheckStatus: String, Codable, Sendable {
    case pass
    case warn
    case fail
}

// MARK: - Formatting

public extension CapabilityReport {
    /// Human-readable table format for discover output.
    func formattedDiscovery() -> String {
        var lines: [String] = []
        lines.append("Host: \(host.hostname) (\(host.platform) \(host.platformVersion), \(host.architecture))")
        lines.append("")
        lines.append("Tools:")
        lines
            .append(
                "  Swift:       \(capabilities.swift.installed ? "✅ \(capabilities.swift.version ?? "")" : "❌ not found")"
            )
        lines
            .append(
                "  Xcode:       \(capabilities.xcode.installed ? "✅ \(capabilities.xcode.version ?? "")" : "❌ not found")"
            )
        lines
            .append(
                "  Git:         \(capabilities.git.installed ? "✅ \(capabilities.git.version ?? "")" : "❌ not found")"
            )
        lines
            .append(
                "  GitHub CLI:  \(capabilities.githubCLI.installed ? "✅ \(capabilities.githubCLI.version ?? "")" : "❌ not found")"
            )
        lines.append("")
        lines.append("Agents:")
        lines.append("  Claude:  \(agents.claude.installed ? "✅" : "⚠️  not found")")
        lines.append("  Codex:   \(agents.codex.installed ? "✅" : "⚠️  not found")")
        lines.append("  Gemini:  \(agents.gemini.installed ? "✅" : "⚠️  not found")")
        lines.append("")
        lines.append("Network:")
        lines.append("  SSH:       \(network.ssh.installed ? "✅" : "❌ not found")")
        lines.append("  Tailscale: \(network.tailscale.installed ? "✅" : "⚠️  not found")")
        lines.append("")
        lines.append("Power:")
        lines.append("  AC Power:    \(power.onACPower ? "✅" : "⚠️  on battery")")
        lines.append("  Sleep Prevented: \(power.preventSleep ? "✅" : "⚠️  sleep enabled")")
        return lines.joined(separator: "\n")
    }

    /// Human-readable table format for doctor output.
    func formattedDoctor() -> String {
        var lines: [String] = []
        lines.append("Doctor Report: \(host.hostname)")
        lines.append("Generated: \(generatedAt)")
        lines.append("")

        let fails = checks.filter { $0.status == .fail }
        let warns = checks.filter { $0.status == .warn }
        let passes = checks.filter { $0.status == .pass }

        if !fails.isEmpty {
            lines.append("❌ Failures (\(fails.count)):")
            for check in fails {
                lines.append("  [\(check.category)] \(check.id): \(check.message)")
            }
            lines.append("")
        }

        if !warns.isEmpty {
            lines.append("⚠️  Warnings (\(warns.count)):")
            for check in warns {
                lines.append("  [\(check.category)] \(check.id): \(check.message)")
            }
            lines.append("")
        }

        lines.append("✅ Passing (\(passes.count))")
        lines.append("")
        lines.append("Summary: \(fails.count) fail, \(warns.count) warn, \(passes.count) pass")

        return lines.joined(separator: "\n")
    }
}
