import Foundation
import Testing
@testable import AnvilRunner

struct CleanupPolicyTests {
    @Test
    func cleanupPolicyCases() {
        let cases: [CleanupPolicy] = [.minimal, .standard, .aggressive, .ephemeral]
        #expect(cases.count == 4)
        #expect(CleanupPolicy.allCases.count == 4)
    }

    @Test
    func cleanupPolicyRawValues() {
        #expect(CleanupPolicy.minimal.rawValue == "minimal")
        #expect(CleanupPolicy.standard.rawValue == "standard")
        #expect(CleanupPolicy.aggressive.rawValue == "aggressive")
        #expect(CleanupPolicy.ephemeral.rawValue == "ephemeral")
    }

    @Test
    func diskUsagePercentReturnsValidRange() async throws {
        let executor = CleanupExecutor()
        let usage = try await executor.diskUsagePercent()

        // Disk usage should be between 0 and 100
        #expect(usage >= 0)
        #expect(usage <= 100)
    }

    @Test
    func minimalCleanupRejectsPathOutsideAllowedRoots() async throws {
        let temporaryRoot = try makeTemporaryDirectory()
        let allowedRoot = temporaryRoot.appending(path: "allowed")
        let outsideRoot = temporaryRoot.appending(path: "outside")
        try FileManager.default.createDirectory(at: allowedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)

        let executor = CleanupExecutor(
            safetyPolicy: CleanupSafetyPolicy(
                allowedRootDirectories: [allowedRoot.path],
                protectedDirectories: [temporaryRoot.path]
            )
        )

        do {
            _ = try await executor.execute(policy: .minimal, workspacePath: outsideRoot.path)
            Issue.record("Expected unsafePath to be thrown")
        } catch let error as CleanupError {
            #expect(error == .unsafePath(outsideRoot.path))
        } catch {
            Issue.record("Expected CleanupError.unsafePath, got \(error)")
        }
    }

    @Test
    func dryRunReportsCleanupWithoutDeletingWorkspace() async throws {
        let temporaryRoot = try makeTemporaryDirectory()
        let workspace = temporaryRoot.appending(path: "runner-workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let executor = CleanupExecutor(
            safetyPolicy: CleanupSafetyPolicy(
                allowedRootDirectories: [temporaryRoot.path],
                protectedDirectories: [],
                dryRun: true
            )
        )

        let result = try await executor.execute(policy: .minimal, workspacePath: workspace.path)

        #expect(result.removedPaths.isEmpty)
        #expect(result.dryRunPaths == [workspace.path])
        #expect(FileManager.default.fileExists(atPath: workspace.path))
    }

    @Test
    func runnerTemporaryItemDetectionIsScoped() {
        #expect(CleanupExecutor.isRunnerTemporaryItem("anvil-runner-123"))
        #expect(CleanupExecutor.isRunnerTemporaryItem("swiftanvil-runner-cache"))
        #expect(CleanupExecutor.isRunnerTemporaryItem("actions-runner-temp"))
        #expect(!CleanupExecutor.isRunnerTemporaryItem("unrelated-cache"))
        #expect(!CleanupExecutor.isRunnerTemporaryItem("runner-actions-temp"))
    }

    @Test
    func additionalAllowedRootsRejectBroadSystemPaths() {
        let policy = CleanupSafetyPolicy.runnerDefault()
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        #expect(!policy.allowsAdditionalRoot("/"))
        #expect(!policy.allowsAdditionalRoot("/Users"))
        #expect(!policy.allowsAdditionalRoot(home))
        #expect(!policy.allowsAdditionalRoot("/System"))
    }

    @Test
    func broadAllowedRootDoesNotOverrideProtectedDirectories() {
        let defaultPolicy = CleanupSafetyPolicy.runnerDefault()
        let policy = CleanupSafetyPolicy(
            allowedRootDirectories: ["/"],
            protectedDirectories: defaultPolicy.protectedDirectories
        )

        #expect(!policy.allowsRemoval(of: "/Users/example"))
    }

    @Test
    func defaultPolicyAllowsCuratedChildrenUnderHomeDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let policy = CleanupSafetyPolicy.runnerDefault()

        #expect(policy.allowsRemoval(of: "\(home)/actions-runner/_work/example"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "anvil-runner-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
