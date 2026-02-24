import Foundation
import Testing
@testable import PromptImproverCore

@Suite(.serialized)
struct LocalCommandRunnerTests {
    @Test
    func returnsLaunchErrorWhenExecutableCannotBeStarted() {
        let runner = LocalCommandRunner()
        let result = runner.run(
            executableURL: URL(fileURLWithPath: "/this/path/does/not/exist"),
            arguments: ["--version"],
            environment: nil,
            timeout: 1
        )

        #expect(result.launchErrorDescription != nil)
        #expect(result.status == -1)
        #expect(result.timedOut == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func marksTimeoutWhenCommandDoesNotFinish() {
        let runner = LocalCommandRunner()
        let timeoutScript = try! TestSupport.makeExecutableScript(
            name: "local-command-runner-timeout",
            script: "#!/bin/sh\nwhile true; do sleep 1; done\n",
            prefix: "LocalCommandRunner"
        )
        defer { TestSupport.removeItemIfPresent(timeoutScript.deletingLastPathComponent()) }

        let result = runner.run(
            executableURL: timeoutScript,
            arguments: [],
            environment: nil,
            timeout: 0.05
        )

        #expect(result.timedOut)
    }
}
