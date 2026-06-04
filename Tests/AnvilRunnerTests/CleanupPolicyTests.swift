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
}
