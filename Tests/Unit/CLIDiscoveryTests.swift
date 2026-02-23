import Foundation
import Testing
@testable import PromptImproverCore

@Suite(.serialized)
struct CLIDiscoveryTests {
    @Test
    func resolveUsesShellPathWhenLookupSucceeds() throws {
        let isolatedHome = try TestSupport.makeTemporaryDirectory(prefix: "CLIDiscoveryHome")
        let executable = try TestSupport.makeExecutableScript(
            name: "codex",
            script: "#!/bin/sh\nexit 0\n",
            prefix: "CLIDiscoveryShell"
        )

        let runner = StubLocalCommandRunner()
        runner.results = [
            LocalCommandResult(
                stdout: executable.path + "\n",
                stderr: "",
                status: 0,
                timedOut: false,
                launchErrorDescription: nil
            )
        ]

        let discovery = CLIDiscovery(
            fileManager: .default,
            homeDirectoryPath: isolatedHome.path,
            localCommandRunner: runner,
            baseCandidatesByTool: [.codex: []]
        )

        let resolved = discovery.resolve(tool: .codex)
        #expect(resolved?.path == executable.path)
    }

    @Test
    func resolveFallsBackToCandidateWhenShellLookupFails() throws {
        let isolatedHome = try TestSupport.makeTemporaryDirectory(prefix: "CLIDiscoveryHome")
        let fallback = try TestSupport.makeExecutableScript(
            name: "claude",
            script: "#!/bin/sh\nexit 0\n",
            prefix: "CLIDiscoveryFallback"
        )

        let runner = StubLocalCommandRunner()
        runner.results = [
            LocalCommandResult(
                stdout: "",
                stderr: "lookup failed",
                status: 1,
                timedOut: false,
                launchErrorDescription: nil
            )
        ]

        let discovery = CLIDiscovery(
            fileManager: .default,
            homeDirectoryPath: isolatedHome.path,
            localCommandRunner: runner,
            baseCandidatesByTool: [.claude: [fallback.path]]
        )

        let resolved = discovery.resolve(tool: .claude)
        #expect(resolved?.path == fallback.path)
    }

    @Test
    func resolveReturnsNilWhenShellAndCandidatesFail() throws {
        let isolatedHome = try TestSupport.makeTemporaryDirectory(prefix: "CLIDiscoveryHome")
        let runner = StubLocalCommandRunner()
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
            homeDirectoryPath: isolatedHome.path,
            localCommandRunner: runner,
            baseCandidatesByTool: [.codex: []]
        )

        #expect(discovery.resolve(tool: .codex) == nil)
    }
}

private final class StubLocalCommandRunner: LocalCommandRunning {
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
                launchErrorDescription: "No result configured"
            )
        }
        return results.removeFirst()
    }
}
