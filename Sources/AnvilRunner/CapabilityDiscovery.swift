import Foundation

/// Read-only host capability discovery.
///
/// Detects installed tools, agents, network configuration, and power state
/// without making any privileged changes.
public actor CapabilityDiscovery {
    public init() { }

    private let fileManager = FileManager.default

    // MARK: - Public API

    /// Performs a full capability scan and returns a report.
    public func discover() async -> CapabilityReport {
        let host = await detectHost()
        let tools = await detectTools()
        let agents = await detectAgents()
        let network = await detectNetwork()
        let power = await detectPower()

        return CapabilityReport(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            host: host,
            capabilities: tools,
            agents: agents,
            network: network,
            power: power,
            checks: []
        )
    }

    /// Runs doctor checks on top of discovery and returns a report with health checks.
    public func doctor() async -> CapabilityReport {
        var report = await discover()
        report.checks = runChecks(report: report)
        return report
    }

    // MARK: - Host Detection

    private func detectHost() async -> HostInfo {
        let platform = detectPlatform()
        let version = detectPlatformVersion()
        let arch = detectArchitecture()
        let hostname = ProcessInfo.processInfo.hostName

        return HostInfo(
            platform: platform,
            platformVersion: version,
            architecture: arch,
            hostname: hostname
        )
    }

    private func detectPlatform() -> String {
        #if os(macOS)
            return "macOS"
        #elseif os(Linux)
            return "Linux"
        #else
            return "Unknown"
        #endif
    }

    private func detectPlatformVersion() -> String {
        #if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sw_vers")
            process.arguments = ["-productVersion"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            } catch {
                return "unknown"
            }
        #else
            return "unknown"
        #endif
    }

    private func detectArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return machine ?? "unknown"
    }

    // MARK: - Tool Detection

    private func detectTools() async -> ToolCapabilities {
        await ToolCapabilities(
            swift: detectTool(named: "swift", versionArgs: ["--version"]),
            xcode: detectXcode(),
            git: detectTool(named: "git", versionArgs: ["--version"]),
            githubCLI: detectGitHubCLI()
        )
    }

    private func detectTool(named name: String, versionArgs: [String]) async -> ToolInfo {
        let path = await which(name)
        guard let path else {
            return ToolInfo(installed: false)
        }

        let version = await runCommand(path, args: versionArgs)
            .flatMap { parseVersion(from: $0, for: name) }

        return ToolInfo(installed: true, version: version, path: path)
    }

    private func detectXcode() async -> ToolInfo {
        #if os(macOS)
            let path = await which("xcodebuild")
            guard let path else {
                return ToolInfo(installed: false)
            }
            let version = await runCommand(path, args: ["-version"])
                .flatMap { parseXcodeVersion(from: $0) }
            return ToolInfo(installed: true, version: version, path: path)
        #else
            return ToolInfo(installed: false)
        #endif
    }

    private func detectGitHubCLI() async -> ToolInfo {
        let path = await which("gh")
        guard let path else {
            return ToolInfo(installed: false)
        }
        let version = await runCommand(path, args: ["--version"])
            .flatMap { parseVersion(from: $0, for: "gh") }
        let authenticated = await isGHAuthenticated(path: path)
        return ToolInfo(installed: true, version: version, path: path, authenticated: authenticated)
    }

    private func isGHAuthenticated(path: String) async -> Bool {
        let result = await runCommand(path, args: ["auth", "status"])
        guard let output = result else { return false }
        return output.contains("Logged in to") || output.contains("✓")
    }

    // MARK: - Agent Detection

    private func detectAgents() async -> AgentCapabilities {
        await AgentCapabilities(
            claude: detectAgent(named: "claude"),
            codex: detectAgent(named: "codex"),
            gemini: detectAgent(named: "gemini")
        )
    }

    private func detectAgent(named name: String) async -> ToolInfo {
        let path = await which(name)
        guard let path else {
            return ToolInfo(installed: false)
        }
        let version = await runCommand(path, args: ["--version"])
            .flatMap { parseVersion(from: $0, for: name) }
        return ToolInfo(installed: true, version: version, path: path)
    }

    // MARK: - Network Detection

    private func detectNetwork() async -> NetworkCapabilities {
        await NetworkCapabilities(
            ssh: detectSSH(),
            tailscale: detectTailscale()
        )
    }

    private func detectSSH() async -> SSHInfo {
        let path = await which("ssh")
        let installed = path != nil
        let keyConfigured = installed && fileManager.fileExists(atPath: "\(NSHomeDirectory())/.ssh")
        return SSHInfo(installed: installed, reachable: installed, keyConfigured: keyConfigured)
    }

    private func detectTailscale() async -> TailscaleInfo {
        let path = await which("tailscale")
        guard let path else {
            return TailscaleInfo(installed: false, running: false, loggedIn: false)
        }
        let running = await isProcessRunning(named: "tailscaled")
        let loggedIn: Bool = if running {
            await isTailscaleLoggedIn(path: path)
        } else {
            false
        }
        return TailscaleInfo(installed: true, running: running, loggedIn: loggedIn)
    }

    private func isTailscaleLoggedIn(path: String) async -> Bool {
        let result = await runCommand(path, args: ["status", "--self"])
        guard let output = result else { return false }
        return !output.contains("Logged out") && !output.contains("not logged in")
    }

    // MARK: - Power Detection

    private func detectPower() async -> PowerCapabilities {
        #if os(macOS)
            let preventSleep = await isSleepPrevented()
            let onAC = await isOnACPower()
            return PowerCapabilities(preventSleep: preventSleep, onACPower: onAC)
        #else
            return PowerCapabilities(preventSleep: false, onACPower: true)
        #endif
    }

    #if os(macOS)
        private func isSleepPrevented() async -> Bool {
            let result = await runCommand("/usr/bin/pmset", args: ["-g", "assertions"])
            guard let output = result else { return false }
            return output.contains("PreventUserIdleSystemSleep")
        }

        private func isOnACPower() async -> Bool {
            let result = await runCommand("/usr/bin/pmset", args: ["-g", "ps"])
            guard let output = result else { return false }
            return output.contains("AC Power")
        }
    #endif

    // MARK: - Doctor Checks

    private func runChecks(report: CapabilityReport) -> [HealthCheck] {
        var checks: [HealthCheck] = []

        // Toolchain checks
        checks.append(makeCheck(
            id: "swift-installed",
            category: "toolchain",
            condition: report.capabilities.swift.installed,
            passMessage: "Swift \(report.capabilities.swift.version ?? "") installed",
            failMessage: "Swift not installed"
        ))

        checks.append(makeCheck(
            id: "xcode-installed",
            category: "toolchain",
            condition: report.capabilities.xcode.installed,
            passMessage: "Xcode \(report.capabilities.xcode.version ?? "") installed",
            failMessage: "Xcode not installed (macOS only)"
        ))

        checks.append(makeCheck(
            id: "git-installed",
            category: "toolchain",
            condition: report.capabilities.git.installed,
            passMessage: "Git \(report.capabilities.git.version ?? "") installed",
            failMessage: "Git not installed"
        ))

        checks.append(makeCheck(
            id: "gh-installed",
            category: "toolchain",
            condition: report.capabilities.githubCLI.installed,
            passMessage: "GitHub CLI \(report.capabilities.githubCLI.version ?? "") installed",
            failMessage: "GitHub CLI not installed"
        ))

        checks.append(makeCheck(
            id: "gh-authenticated",
            category: "toolchain",
            condition: report.capabilities.githubCLI.authenticated == true,
            passMessage: "GitHub CLI authenticated",
            failMessage: "GitHub CLI not authenticated — run `gh auth login` or see `agents.diagnostics`"
        ))

        // Agent checks (optional — warn only)
        checks.append(makeCheck(
            id: "claude-available",
            category: "agent",
            condition: report.agents.claude.installed,
            passMessage: "Claude CLI available",
            warnMessage: "Claude CLI not installed (optional)"
        ))

        checks.append(makeCheck(
            id: "codex-available",
            category: "agent",
            condition: report.agents.codex.installed,
            passMessage: "Codex CLI available",
            warnMessage: "Codex CLI not installed (optional)"
        ))

        checks.append(makeCheck(
            id: "gemini-available",
            category: "agent",
            condition: report.agents.gemini.installed,
            passMessage: "Gemini CLI available",
            warnMessage: "Gemini CLI not installed (optional)"
        ))

        // Network checks
        checks.append(makeCheck(
            id: "ssh-installed",
            category: "network",
            condition: report.network.ssh.installed,
            passMessage: "SSH installed",
            failMessage: "SSH not installed"
        ))

        checks.append(makeCheck(
            id: "ssh-key-configured",
            category: "network",
            condition: report.network.ssh.keyConfigured,
            passMessage: "SSH keys configured",
            failMessage: "No SSH keys found in ~/.ssh"
        ))

        checks.append(makeCheck(
            id: "tailscale-installed",
            category: "network",
            condition: report.network.tailscale.installed,
            passMessage: "Tailscale installed",
            warnMessage: "Tailscale not installed (optional)"
        ))

        checks.append(makeCheck(
            id: "tailscale-running",
            category: "network",
            condition: report.network.tailscale.running,
            passMessage: "Tailscale daemon running",
            warnMessage: "Tailscale not running"
        ))

        // Power checks
        checks.append(makeCheck(
            id: "ac-power",
            category: "power",
            condition: report.power.onACPower,
            passMessage: "On AC power",
            warnMessage: "On battery power"
        ))

        return checks
    }

    private func makeCheck(
        id: String,
        category: String,
        condition: Bool,
        passMessage: String,
        failMessage: String
    ) -> HealthCheck {
        HealthCheck(
            id: id,
            category: category,
            status: condition ? .pass : .fail,
            message: condition ? passMessage : failMessage
        )
    }

    private func makeCheck(
        id: String,
        category: String,
        condition: Bool,
        passMessage: String,
        warnMessage: String
    ) -> HealthCheck {
        HealthCheck(
            id: id,
            category: category,
            status: condition ? .pass : .warn,
            message: condition ? passMessage : warnMessage
        )
    }

    // MARK: - Helpers

    private func which(_ command: String) async -> String? {
        let result = await runCommand("/usr/bin/which", args: [command])
        return result?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isProcessRunning(named: String) async -> Bool {
        let result = await runCommand("/usr/bin/pgrep", args: ["-x", named])
        return result != nil && !result!.isEmpty
    }

    private func runCommand(_ path: String, args: [String]) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func parseVersion(from output: String, for _: String) -> String? {
        let lines = output.split(separator: "\n")
        guard let firstLine = lines.first else { return nil }
        let line = String(firstLine)

        // Try to extract a semver-like version
        let pattern = #/\d+\.\d+(\.\d+)?/#
        if let match = line.firstMatch(of: pattern) {
            return String(match.0)
        }
        return nil
    }

    private func parseXcodeVersion(from output: String) -> String? {
        let lines = output.split(separator: "\n")
        guard let firstLine = lines.first else { return nil }
        let line = String(firstLine)
        // "Xcode 16.2\nBuild version 16C5032a"
        let pattern = #/Xcode\s+(\d+\.\d+)/#
        if let match = line.firstMatch(of: pattern) {
            return String(match.1)
        }
        return nil
    }
}
