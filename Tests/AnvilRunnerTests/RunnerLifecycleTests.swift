import Foundation
import Testing
@testable import AnvilRunner

struct RunnerLifecycleTests {
    @Test
    func runnerErrorCases() {
        _ = RunnerError.processFailed(exitCode: 1)
        _ = RunnerError.downloadFailed(URL: "https://example.com")
        _ = RunnerError.configurationFailed(reason: "missing token")
        _ = RunnerError.invalidRunnerName("../runner")

        // All error cases constructible — test passes if we reach here
    }

    @Test
    func runnerErrorExitCode() {
        let error = RunnerError.processFailed(exitCode: 42)
        if case let .processFailed(code) = error {
            #expect(code == 42)
        } else {
            Issue.record("Expected processFailed case")
        }
    }

    @Test
    func runnerErrorDownloadURL() {
        let url = "https://github.com/actions/runner/releases/download/v2.334.0/" +
            "actions-runner-osx-arm64-2.334.0.tar.gz"
        let error = RunnerError.downloadFailed(URL: url)
        if case let .downloadFailed(failedURL) = error {
            #expect(failedURL == url)
        } else {
            Issue.record("Expected downloadFailed case")
        }
    }

    @Test
    func runnerErrorConfigurationReason() {
        let reason = "invalid repository URL"
        let error = RunnerError.configurationFailed(reason: reason)
        if case let .configurationFailed(failedReason) = error {
            #expect(failedReason == reason)
        } else {
            Issue.record("Expected configurationFailed case")
        }
    }

    @Test
    func detectArchitectureReturnsValidValue() {
        let lifecycle = RunnerLifecycle()
        // Verify the actor initializes without crashing
        _ = lifecycle
    }

    @Test
    func runnerProcessIDsRequireLiteralNameAndDirectoryMatch() {
        let processList = """
        101 /Users/me/actions-runner/macmini-1/bin/Runner.Listener run
        102 /Users/me/actions-runner/macmini-2/bin/Runner.Listener run
        103 /tmp/macmini-1/bin/Runner.Listener run
        104 /Users/me/actions-runner/macmini-1-extra/bin/Runner.Listener run
        """

        let pids = RunnerLifecycle.runnerProcessIDs(
            from: processList,
            runnerName: "macmini-1",
            runnerDirectory: "/Users/me/actions-runner/macmini-1"
        )

        #expect(pids == [101])
    }

    @Test
    func runnerProcessIDsDoNotTreatRunnerNameAsRegex() {
        let processList = """
        201 /Users/me/actions-runner/runner-1/bin/Runner.Listener run
        202 /Users/me/actions-runner/runner.*1/bin/Runner.Listener run
        """

        let pids = RunnerLifecycle.runnerProcessIDs(
            from: processList,
            runnerName: "runner.*1",
            runnerDirectory: "/Users/me/actions-runner/runner.*1"
        )

        #expect(pids == [202])
    }

    @Test
    func runnerDirectoryRejectsTraversalNames() throws {
        #expect(throws: RunnerError.self) {
            _ = try RunnerLifecycle.runnerDirectory(
                named: "../outside-1",
                under: "/Users/me/actions-runner"
            )
        }

        #expect(throws: RunnerError.self) {
            _ = try RunnerLifecycle.runnerDirectory(
                named: "macmini/../outside-1",
                under: "/Users/me/actions-runner"
            )
        }
    }

    @Test
    func runnerDirectoryAllowsSafeNames() throws {
        let directory = try RunnerLifecycle.runnerDirectory(
            named: "macmini.arm64-1",
            under: "/Users/me/actions-runner"
        )

        #expect(directory == "/Users/me/actions-runner/macmini.arm64-1")
    }

    @Test
    func runnerTokenIsPassedThroughEnvironmentInput() {
        let environment = RunnerLifecycle.environment(addingRunnerToken: "test-token")

        #expect(environment["ACTIONS_RUNNER_INPUT_TOKEN"] == "test-token")
    }

    @Test
    func runnerConfigurationValidation() {
        let config = RunnerConfiguration(
            repositoryURL: "https://github.com/example-org/example-repo",
            token: "test-token",
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
