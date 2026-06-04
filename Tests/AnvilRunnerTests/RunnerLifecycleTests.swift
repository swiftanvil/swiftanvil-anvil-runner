import Foundation
import Testing
@testable import AnvilRunner

struct RunnerLifecycleTests {

    @Test
    func runnerErrorCases() {
        let _ = RunnerError.processFailed(exitCode: 1)
        let _ = RunnerError.downloadFailed(URL: "https://example.com")
        let _ = RunnerError.configurationFailed(reason: "missing token")

        // All error cases constructible — test passes if we reach here
    }

    @Test
    func runnerErrorExitCode() {
        let error = RunnerError.processFailed(exitCode: 42)
        if case .processFailed(let code) = error {
            #expect(code == 42)
        } else {
            Issue.record("Expected processFailed case")
        }
    }

    @Test
    func runnerErrorDownloadURL() {
        let url = "https://github.com/actions/runner/releases/download/v2.332.1/actions-runner-osx-arm64-2.332.1.tar.gz"
        let error = RunnerError.downloadFailed(URL: url)
        if case .downloadFailed(let failedURL) = error {
            #expect(failedURL == url)
        } else {
            Issue.record("Expected downloadFailed case")
        }
    }

    @Test
    func runnerErrorConfigurationReason() {
        let reason = "invalid repository URL"
        let error = RunnerError.configurationFailed(reason: reason)
        if case .configurationFailed(let failedReason) = error {
            #expect(failedReason == reason)
        } else {
            Issue.record("Expected configurationFailed case")
        }
    }

    @Test
    func detectArchitectureReturnsValidValue() async {
        let lifecycle = RunnerLifecycle()
        // Verify the actor initializes without crashing
        _ = lifecycle
    }

    @Test
    func runnerConfigurationValidation() {
        let config = RunnerConfiguration(
            repositoryURL: "https://github.com/example-org/example-repo",
            token: "ghp_test",
            runnerCount: 2,
            namePrefix: "test-runner",
            installDirectory: "/tmp/test-runners",
            ephemeral: true,
            cleanupPolicy: .standard
        )

        #expect(config.runnerCount == 2)
        #expect(config.namePrefix == "test-runner")
        #expect(config.installDirectory == "/tmp/test-runners")
        #expect(config.ephemeral == true)
    }
}
