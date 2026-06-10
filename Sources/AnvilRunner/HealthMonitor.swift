import Foundation

/// Monitors the health of self-hosted runner instances.
public actor HealthMonitor {
    public init() { }

    /// Checks the health of a runner and returns its status.
    public func checkRunner(name: String, installDirectory: String) async -> RunnerStatus {
        let isRunning = await isProcessRunning(name: name, installDirectory: installDirectory)
        let diskUsage = await (try? CleanupExecutor().diskUsagePercent()) ?? 0
        let memoryUsage = await (try? memoryUsagePercent()) ?? 0

        return RunnerStatus(
            name: name,
            isRunning: isRunning,
            lastJobCompletedAt: nil, // Would be populated by job hook
            diskUsagePercent: diskUsage,
            memoryUsagePercent: memoryUsage
        )
    }

    /// Checks all runners in a fleet.
    public func checkFleet(installDirectory: String, count: Int, namePrefix: String) async -> [RunnerStatus] {
        var results: [RunnerStatus] = []
        for i in 1 ... max(1, count) {
            let name = "\(namePrefix)-\(i)"
            let status = await checkRunner(name: name, installDirectory: installDirectory)
            results.append(status)
        }
        return results
    }

    /// Returns true if disk usage exceeds the threshold.
    public func isDiskCritical(threshold: Int = 80) async -> Bool {
        let usage = await (try? CleanupExecutor().diskUsagePercent()) ?? 0
        return usage >= threshold
    }

    /// Returns true if memory usage exceeds the threshold.
    public func isMemoryCritical(threshold: Int = 90) async -> Bool {
        let usage = await (try? memoryUsagePercent()) ?? 0
        return usage >= threshold
    }

    /// Formats a status report for display.
    public func formatReport(_ statuses: [RunnerStatus]) -> String {
        var lines: [String] = []
        lines.append("Runner Health Report")
        lines.append(String(repeating: "=", count: 50))

        for status in statuses {
            let state = status.isRunning ? "🟢 Running" : "🔴 Stopped"
            let disk = status.diskUsagePercent >= 80
                ? "⚠️ \(status.diskUsagePercent)%"
                : "\(status.diskUsagePercent)%"
            let memory = status.memoryUsagePercent >= 90
                ? "⚠️ \(status.memoryUsagePercent)%"
                : "\(status.memoryUsagePercent)%"

            lines.append("""
            \(status.name):
              State:   \(state)
              Disk:    \(disk)
              Memory:  \(memory)
            """)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func isProcessRunning(name: String, installDirectory: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-fl", "Runner.Listener"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return false
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let runnerDirectory = try RunnerLifecycle.runnerDirectory(named: name, under: installDirectory)
            return !RunnerLifecycle.runnerProcessIDs(
                from: output,
                runnerName: name,
                runnerDirectory: runnerDirectory
            ).isEmpty
        } catch {
            return false
        }
    }

    private func memoryUsagePercent() async throws -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/vm_stat")

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return 0
        }

        // Parse vm_stat output to calculate memory usage percentage
        // This is a simplified calculation
        var freePages: UInt64 = 0
        var activePages: UInt64 = 0
        var inactivePages: UInt64 = 0
        var wiredPages: UInt64 = 0

        let lines = output.split(separator: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Pages free:") {
                freePages = extractPageCount(from: trimmed) ?? 0
            } else if trimmed.hasPrefix("Pages active:") {
                activePages = extractPageCount(from: trimmed) ?? 0
            } else if trimmed.hasPrefix("Pages inactive:") {
                inactivePages = extractPageCount(from: trimmed) ?? 0
            } else if trimmed.hasPrefix("Pages wired down:") {
                wiredPages = extractPageCount(from: trimmed) ?? 0
            }
        }

        let totalPages = freePages + activePages + inactivePages + wiredPages
        guard totalPages > 0 else { return 0 }

        let usedPages = activePages + inactivePages + wiredPages
        return Int((Double(usedPages) / Double(totalPages)) * 100)
    }

    private func extractPageCount(from line: String) -> UInt64? {
        let components = line.split(separator: ":")
        guard components.count >= 2 else { return nil }
        let valueStr = components[1].trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ".", with: "")
        return UInt64(valueStr)
    }
}
