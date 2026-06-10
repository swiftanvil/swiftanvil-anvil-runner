import Foundation
import Testing
@testable import AnvilRunner

struct RunnerConfigurationTests {
    @Test
    func defaultConfiguration() {
        let config = RunnerConfiguration(
            repositoryURL: "https://github.com/example-org/example-repo",
            token: "test-token"
        )

        #expect(config.repositoryURL == "https://github.com/example-org/example-repo")
        #expect(config.token == "test-token")
        #expect(config.runnerCount == 1)
        #expect(config.namePrefix == "macmini")
        #expect(config.ephemeral == true)
        #expect(config.cleanupPolicy == .standard)
        #expect(config.memoryLimitGB == 8)
        #expect(config.diskAlertThreshold == 80)
        #expect(config.labels == ["self-hosted", "macOS", "arm64"])
    }

    @Test
    func customConfiguration() {
        let config = RunnerConfiguration(
            repositoryURL: "https://github.com/example-org/example-repo",
            token: "test-token",
            runnerCount: 3,
            namePrefix: "ci-runner",
            installDirectory: "~/custom-runners",
            ephemeral: false,
            cleanupPolicy: .aggressive,
            memoryLimitGB: 16,
            diskAlertThreshold: 90,
            labels: ["self-hosted", "linux"]
        )

        #expect(config.runnerCount == 3)
        #expect(config.namePrefix == "ci-runner")
        #expect(config.ephemeral == false)
        #expect(config.cleanupPolicy == .aggressive)
        #expect(config.memoryLimitGB == 16)
        #expect(config.diskAlertThreshold == 90)
        #expect(config.labels == ["self-hosted", "linux"])
    }

    @Test
    func installDirectoryExpandsTilde() {
        let config = RunnerConfiguration(
            repositoryURL: "https://github.com/example-org/example-repo",
            token: "test-token",
            installDirectory: "~/actions-runner"
        )

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(config.installDirectory == "\(home)/actions-runner")
    }

    @Test
    func runnerCountMinimumIsOne() {
        let config = RunnerConfiguration(
            repositoryURL: "https://github.com/example-org/example-repo",
            token: "test-token",
            runnerCount: 0
        )

        #expect(config.runnerCount == 1)
    }

    @Test
    func diskAlertThresholdClamped() {
        let over = RunnerConfiguration(
            repositoryURL: "https://github.com/example-org/example-repo",
            token: "test-token",
            diskAlertThreshold: 150
        )
        #expect(over.diskAlertThreshold == 100)

        let under = RunnerConfiguration(
            repositoryURL: "https://github.com/example-org/example-repo",
            token: "test-token",
            diskAlertThreshold: -10
        )
        #expect(under.diskAlertThreshold == 0)
    }
}
