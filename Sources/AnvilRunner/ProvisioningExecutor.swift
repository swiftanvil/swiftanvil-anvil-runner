import Foundation

/// Applies provisioning plans safely with explicit user consent and audit logging.
///
/// Design principles:
/// - Dry-run by default — call `apply(dryRun: false)` to make real changes.
/// - Privileged changes require explicit confirmation.
/// - Every action is logged to an audit trail.
/// - No secrets are stored or logged.
public actor ProvisioningExecutor {
    private var auditLog: [AuditEntry] = []

    public init() {}

    /// Applies a provisioning plan.
    /// - Parameters:
    ///   - plan: The plan to apply.
    ///   - dryRun: If true, reports what would change without making changes.
    ///   - autoConfirm: If true, skips interactive prompts (use with care).
    /// - Returns: The result of applying the plan.
    public func apply(
        plan: ProvisioningPlan,
        dryRun: Bool = true,
        autoConfirm: Bool = false
    ) async -> ProvisioningResult {
        var result = ProvisioningResult()

        if plan.isNoOp {
            return result
        }

        // Print plan summary
        printPlan(plan, dryRun: dryRun)

        // Confirm if there are privileged changes and not in auto-confirm mode
        let hasPrivileged = plan.changes.contains { $0.isPrivileged }
        if hasPrivileged && !autoConfirm && !dryRun {
            let confirmed = await promptForConfirmation(
                message: "\nThis plan contains privileged changes. Apply them?"
            )
            if !confirmed {
                result.skippedChanges = plan.changes.map(\.id)
                return result
            }
        }

        // Apply changes
        for change in plan.changes {
            if dryRun {
                result.skippedChanges.append(change.id)
                log(changeID: change.id, status: "dry-run")
            } else {
                do {
                    try await execute(change: change)
                    result.appliedChanges.append(change.id)
                    log(changeID: change.id, status: "applied")
                } catch {
                    result.errors.append(ProvisioningError(
                        changeID: change.id,
                        message: String(describing: error)
                    ))
                    log(changeID: change.id, status: "failed")
                }
            }
        }

        // Print guidance
        if !plan.guidance.isEmpty {
            print("\n📋 Manual steps required:")
            for guide in plan.guidance {
                print("  [\(guide.category)] \(guide.message)")
                if let url = guide.documentationURL {
                    print("    → \(url)")
                }
            }
        }

        result.auditLog = auditLog
        return result
    }

    /// Returns the current audit log.
    public func auditLogEntries() -> [AuditEntry] {
        auditLog
    }

    // MARK: - Private

    private func printPlan(_ plan: ProvisioningPlan, dryRun: Bool) {
        let mode = dryRun ? "DRY RUN" : "LIVE"
        print("\n🛠  Provisioning Plan: \(plan.profileName) [\(mode)]")
        print(String(repeating: "─", count: 50))

        if !plan.changes.isEmpty {
            print("\nChanges (\(plan.changes.count)):")
            for change in plan.changes {
                let priv = change.isPrivileged ? " 🔒" : ""
                print("  [\(change.category)] \(change.description)\(priv)")
                if let cmd = change.command {
                    print("    → \(cmd)")
                }
            }
        }

        if !plan.guidance.isEmpty {
            print("\nGuidance (\(plan.guidance.count)):")
            for guide in plan.guidance {
                print("  [\(guide.category)] \(guide.message)")
            }
        }

        if plan.isNoOp {
            print("\n✅ No changes needed. Host already matches profile.")
        }
    }

    private func execute(change: PlannedChange) async throws {
        guard let command = change.command else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ProvisioningError(
                changeID: change.id,
                message: "Command exited with status \(process.terminationStatus)"
            )
        }
    }

    private func log(changeID: String, status: String) {
        let entry = AuditEntry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            changeID: changeID,
            status: status
        )
        auditLog.append(entry)
    }

    private func promptForConfirmation(message: String) async -> Bool {
        print(message + " (yes/no): ", terminator: "")
        guard let response = readLine()?.lowercased() else { return false }
        return response == "yes" || response == "y"
    }
}
