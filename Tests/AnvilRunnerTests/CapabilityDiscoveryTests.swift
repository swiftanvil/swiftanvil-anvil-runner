import Foundation
import Testing
@testable import AnvilRunner

@Suite("CapabilityDiscovery")
struct CapabilityDiscoveryTests {
    @Test("discover produces a report with schema version 1")
    func discoverProducesReport() async {
        let discovery = CapabilityDiscovery()
        let report = await discovery.discover()

        #expect(report.schemaVersion == 1)
        #expect(!report.generatedAt.isEmpty)
        #expect(!report.host.platform.isEmpty)
        #expect(!report.host.hostname.isEmpty)
    }

    @Test("doctor produces checks")
    func doctorProducesChecks() async {
        let discovery = CapabilityDiscovery()
        let report = await discovery.doctor()

        #expect(!report.checks.isEmpty)
    }

    @Test("doctor checks have valid statuses")
    func doctorChecksHaveValidStatuses() async {
        let discovery = CapabilityDiscovery()
        let report = await discovery.doctor()

        for check in report.checks {
            #expect([CheckStatus.pass, .warn, .fail].contains(check.status))
            #expect(!check.id.isEmpty)
            #expect(!check.category.isEmpty)
            #expect(!check.message.isEmpty)
        }
    }

    @Test("report JSON round-trips correctly")
    func reportJSONRoundTrip() async throws {
        let discovery = CapabilityDiscovery()
        let report = await discovery.discover()

        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CapabilityReport.self, from: data)

        #expect(decoded.schemaVersion == report.schemaVersion)
        #expect(decoded.host.hostname == report.host.hostname)
        #expect(decoded.host.platform == report.host.platform)
    }

    @Test("formattedDiscovery produces non-empty output")
    func formattedDiscoveryNonEmpty() async {
        let discovery = CapabilityDiscovery()
        let report = await discovery.discover()
        let output = report.formattedDiscovery()

        #expect(!output.isEmpty)
        #expect(output.contains("Host:"))
    }

    @Test("formattedDoctor produces non-empty output")
    func formattedDoctorNonEmpty() async {
        let discovery = CapabilityDiscovery()
        let report = await discovery.doctor()
        let output = report.formattedDoctor()

        #expect(!output.isEmpty)
        #expect(output.contains("Doctor Report:"))
    }

    @Test("doctor exit logic: pass when no failures")
    func doctorNoFailures() {
        let report = CapabilityReport(
            generatedAt: "2026-06-04T00:00:00Z",
            host: HostInfo(platform: "macOS", platformVersion: "15.5", architecture: "arm64", hostname: "test"),
            capabilities: ToolCapabilities(
                swift: ToolInfo(installed: true, version: "6.0"),
                xcode: ToolInfo(installed: true, version: "16.0"),
                git: ToolInfo(installed: true, version: "2.47"),
                githubCLI: ToolInfo(installed: true, version: "2.67", authenticated: true)
            ),
            agents: AgentCapabilities(
                claude: ToolInfo(installed: false),
                codex: ToolInfo(installed: false),
                gemini: ToolInfo(installed: false)
            ),
            network: NetworkCapabilities(
                ssh: SSHInfo(installed: true, reachable: true, keyConfigured: true),
                tailscale: TailscaleInfo(installed: false, running: false, loggedIn: false)
            ),
            power: PowerCapabilities(preventSleep: true, onACPower: true),
            checks: [
                HealthCheck(id: "swift-installed", category: "toolchain", status: .pass, message: "OK"),
                HealthCheck(id: "gemini-available", category: "agent", status: .warn, message: "Optional")
            ]
        )

        let hasFailures = report.checks.contains { $0.status == CheckStatus.fail }
        #expect(!hasFailures)
    }

    @Test("doctor exit logic: fail when failures present")
    func doctorWithFailures() {
        let report = CapabilityReport(
            generatedAt: "2026-06-04T00:00:00Z",
            host: HostInfo(platform: "macOS", platformVersion: "15.5", architecture: "arm64", hostname: "test"),
            capabilities: ToolCapabilities(
                swift: ToolInfo(installed: false),
                xcode: ToolInfo(installed: false),
                git: ToolInfo(installed: true),
                githubCLI: ToolInfo(installed: true, authenticated: false)
            ),
            agents: AgentCapabilities(
                claude: ToolInfo(installed: false),
                codex: ToolInfo(installed: false),
                gemini: ToolInfo(installed: false)
            ),
            network: NetworkCapabilities(
                ssh: SSHInfo(installed: true, reachable: true, keyConfigured: true),
                tailscale: TailscaleInfo(installed: false, running: false, loggedIn: false)
            ),
            power: PowerCapabilities(preventSleep: true, onACPower: true),
            checks: [
                HealthCheck(id: "swift-installed", category: "toolchain", status: .fail, message: "Missing"),
                HealthCheck(id: "gh-authenticated", category: "toolchain", status: .fail, message: "Not auth")
            ]
        )

        let hasFailures = report.checks.contains { $0.status == CheckStatus.fail }
        #expect(hasFailures)
    }
}
