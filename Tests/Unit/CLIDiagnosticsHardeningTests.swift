import Foundation
import Testing
@testable import PromptImproverCore

@Suite(.serialized)
struct CLIDiagnosticsHardeningTests {
    @Test
    func discoveryFallsBackToNvmClaudeWhenShellLookupTimesOut() throws {
        let homeDirectory = try TestSupport.makeTemporaryDirectory(prefix: "DiscoveryHome")
        let claudeExecutable = homeDirectory
            .appendingPathComponent(".nvm/versions/node/v20.10.0/bin/claude")
        try TestSupport.writeExecutableScript(at: claudeExecutable, script: "#!/bin/sh\nexit 0\n")

        let runner = FakeLocalCommandRunner()
        runner.results = [
            LocalCommandResult(
                stdout: "",
                stderr: "",
                status: -1,
                timedOut: true,
                launchErrorDescription: nil
            )
        ]

        let discovery = CLIDiscovery(
            fileManager: .default,
            homeDirectoryPath: homeDirectory.path,
            localCommandRunner: runner,
            baseCandidatesByTool: [.claude: []]
        )

        let resolved = discovery.resolve(tool: .claude)

        let resolvedPath = resolved?.resolvingSymlinksInPath().path
        let expectedPath = claudeExecutable.resolvingSymlinksInPath().path
        #expect(resolvedPath == expectedPath)
    }

    @Test
    func healthCheckReportsTimeoutWithoutBlocking() {
        let runner = FakeLocalCommandRunner()
        runner.results = [
            LocalCommandResult(
                stdout: "",
                stderr: "",
                status: -1,
                timedOut: true,
                launchErrorDescription: nil
            )
        ]

        let healthCheck = CLIHealthCheck(localCommandRunner: runner, commandTimeout: 0.01)
        let executableURL = URL(fileURLWithPath: "/tmp/fake-codex-timeout")
        let availability = healthCheck.check(tool: .codex, executableURL: executableURL)

        #expect(availability.installed)
        #expect(availability.version == nil)
        #expect(availability.healthMessage?.contains("timed out") == true)
    }

    @Test
    func codexCapabilityDetectionTimeoutStillUsesVersionFallback() throws {
        let executableURL = try TestSupport.makeExecutableScript(
            name: "codex-capability-timeout",
            script: "#!/bin/sh\nexit 0\n",
            prefix: "CLIDiagnostics"
        )
        let runner = FakeLocalCommandRunner()
        runner.results = [
            LocalCommandResult(
                stdout: "",
                stderr: "",
                status: -1,
                timedOut: true,
                launchErrorDescription: nil
            )
        ]

        let detector = ToolCapabilityDetector(
            fileManager: .default,
            localCommandRunner: runner,
            commandTimeout: 0.01
        )
        let signature = try #require(
            detector.makeSignature(
                tool: .codex,
                executableURL: executableURL,
                versionString: "codex-cli 0.200.0"
            )
        )

        let capabilities = detector.detectCapabilities(
            tool: .codex,
            executableURL: executableURL,
            signature: signature
        )

        #expect(capabilities.supportsModelFlag == false)
        #expect(capabilities.supportsEffortConfig == true)
        #expect(capabilities.supportedEffortValues == EngineEffort.allCases)
    }
}

private final class FakeLocalCommandRunner: LocalCommandRunning {
    var results: [LocalCommandResult] = []

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval
    ) -> LocalCommandResult {
        if results.isEmpty {
            return LocalCommandResult(
                stdout: "",
                stderr: "",
                status: -1,
                timedOut: false,
                launchErrorDescription: "No fake runner result configured"
            )
        }
        return results.removeFirst()
    }
}
