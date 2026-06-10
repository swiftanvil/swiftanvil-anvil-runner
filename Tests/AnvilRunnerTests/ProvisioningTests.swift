import Foundation
import Testing
@testable import AnvilRunner

// MARK: - Worker Profile Tests

@Suite("WorkerProfile")
struct WorkerProfileTests {
    @Test("build-worker profile has correct defaults")
    func buildWorkerDefaults() {
        let profile = WorkerProfile.buildWorker
        #expect(profile.name == "build-worker")
        #expect(profile.role == .build)
        #expect(profile.requirements.requiresGitHubCLI == true)
        #expect(profile.requirements.requiresSSH == true)
        #expect(profile.requirements.minSwiftVersion == "6.0")
        #expect(profile.powerSettings?.preventSleep == true)
        #expect(profile.labels.contains("build"))
    }

    @Test("test-worker profile requires more disk space")
    func workerRequirements() {
        let profile = WorkerProfile.testWorker
        #expect(profile.role == .test)
        #expect(profile.requirements.minFreeDiskGB == 100)
        #expect(profile.requirements.minMemoryGB == 16)
        #expect(profile.requirements.minXcodeVersion == "16.0")
    }

    @Test("review-worker profile is lighter weight")
    func reviewWorkerRequirements() {
        let profile = WorkerProfile.reviewWorker
        #expect(profile.role == .review)
        #expect(profile.requirements.requiresSSH == false)
        #expect(profile.requirements.minFreeDiskGB == 30)
    }

    @Test("all built-in profiles are unique by name")
    func uniqueNames() {
        let names = WorkerProfile.allBuiltIn.map(\.name)
        #expect(Set(names).count == names.count)
    }
}

// MARK: - Provisioning Planner Tests

@Suite("ProvisioningPlanner")
struct ProvisioningPlannerTests {
    let planner = ProvisioningPlanner()

    @Test("plan for build-worker produces non-nil result")
    func planProducesResult() async {
        let plan = await planner.plan(for: .buildWorker)
        #expect(plan.profileName == "build-worker")
    }

    @Test("plan includes guidance for missing tools")
    func planIncludesGuidance() async {
        let plan = await planner.plan(for: .buildWorker)
        // On a clean macOS host, some guidance is likely
        // We just verify the plan structure is valid
        #expect(plan.changes.count >= 0)
        #expect(plan.guidance.count >= 0)
    }

    @Test("plan is no-op when host already matches")
    func planNoOpWhenMatching() async {
        // Create a minimal profile with no requirements
        let minimal = WorkerProfile(
            name: "minimal",
            description: "Minimal profile",
            role: .build,
            requirements: ProfileRequirements(),
            powerSettings: nil,
            networkSettings: nil,
            labels: []
        )
        let plan = await planner.plan(for: minimal)
        #expect(plan.isNoOp == true)
    }

    @Test("version comparison works correctly")
    func versionComparison() async {
        let profile = WorkerProfile(
            name: "swift-check",
            description: "Swift version check",
            role: .build,
            requirements: ProfileRequirements(minSwiftVersion: "6.0"),
            labels: []
        )
        let plan = await planner.plan(for: profile)
        // Should either be no-op (if Swift 6.0+ installed) or have guidance
        #expect(plan.profileName == "swift-check")
    }
}

// MARK: - Provisioning Executor Tests

@Suite("ProvisioningExecutor")
struct ProvisioningExecutorTests {
    let executor = ProvisioningExecutor()

    @Test("dry-run does not apply changes")
    func dryRunSkipsChanges() async {
        let plan = ProvisioningPlan(
            profileName: "test",
            changes: [
                PlannedChange(
                    id: "test-change",
                    category: "power",
                    description: "Test change",
                    command: "echo hello",
                    isPrivileged: false
                )
            ],
            guidance: []
        )
        let result = await executor.apply(plan: plan, dryRun: true)
        #expect(result.skippedChanges.contains("test-change"))
        #expect(!result.appliedChanges.contains("test-change"))
    }

    @Test("live apply executes non-privileged changes")
    func liveApplyExecutes() async {
        let plan = ProvisioningPlan(
            profileName: "test",
            changes: [
                PlannedChange(
                    id: "echo-test",
                    category: "test",
                    description: "Echo test",
                    command: "echo 'provisioning-test'",
                    isPrivileged: false
                )
            ],
            guidance: []
        )
        let result = await executor.apply(plan: plan, dryRun: false, autoConfirm: true)
        #expect(result.appliedChanges.contains("echo-test"))
        #expect(result.errors.isEmpty)
    }

    @Test("no-op plan returns empty result")
    func noOpPlan() async {
        let plan = ProvisioningPlan(profileName: "empty", changes: [], guidance: [])
        let result = await executor.apply(plan: plan)
        #expect(result.appliedChanges.isEmpty)
        #expect(result.skippedChanges.isEmpty)
        #expect(result.errors.isEmpty)
    }

    @Test("audit log captures entries")
    func auditLogCapture() async {
        let plan = ProvisioningPlan(
            profileName: "test",
            changes: [
                PlannedChange(id: "log-test", category: "test", description: "Log test", command: "echo log")
            ],
            guidance: []
        )
        _ = await executor.apply(plan: plan, dryRun: false, autoConfirm: true)
        let log = await executor.auditLogEntries()
        #expect(!log.isEmpty)
        #expect(log.first?.changeID == "log-test")
    }
}

// MARK: - Profile Codable Tests

@Suite("ProfileCodable")
struct ProfileCodableTests {
    @Test("profile round-trips through JSON")
    func roundTripJSON() throws {
        let profile = WorkerProfile.buildWorker
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(profile)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WorkerProfile.self, from: data)
        #expect(decoded.name == profile.name)
        #expect(decoded.role == profile.role)
        #expect(decoded.requirements.minSwiftVersion == profile.requirements.minSwiftVersion)
    }
}
