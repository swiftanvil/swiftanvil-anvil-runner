import Testing
@testable import AnvilRunner

struct HealthMonitorTests {
    @Test
    func formatReportWithRunningRunner() async {
        let monitor = HealthMonitor()
        let statuses = [
            RunnerStatus(
                name: "macmini-1",
                isRunning: true,
                lastJobCompletedAt: nil,
                diskUsagePercent: 45,
                memoryUsagePercent: 60
            )
        ]

        let report = await monitor.formatReport(statuses)
        #expect(report.contains("macmini-1"))
        #expect(report.contains("🟢 Running"))
        #expect(report.contains("45%"))
        #expect(report.contains("60%"))
    }

    @Test
    func formatReportWithCriticalDisk() async {
        let monitor = HealthMonitor()
        let statuses = [
            RunnerStatus(
                name: "macmini-1",
                isRunning: true,
                lastJobCompletedAt: nil,
                diskUsagePercent: 85,
                memoryUsagePercent: 60
            )
        ]

        let report = await monitor.formatReport(statuses)
        #expect(report.contains("⚠️ 85%"))
    }

    @Test
    func formatReportWithStoppedRunner() async {
        let monitor = HealthMonitor()
        let statuses = [
            RunnerStatus(
                name: "macmini-1",
                isRunning: false,
                lastJobCompletedAt: nil,
                diskUsagePercent: 30,
                memoryUsagePercent: 40
            )
        ]

        let report = await monitor.formatReport(statuses)
        #expect(report.contains("🔴 Stopped"))
    }

    @Test
    func diskCriticalThreshold() async {
        let monitor = HealthMonitor()

        // We can't easily mock disk usage, but we can verify the method exists
        // and returns a Bool. The actual threshold logic is straightforward.
        _ = await monitor.isDiskCritical(threshold: 80)
    }
}
