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

    @Test
    func marksTimeoutWhenCommandDoesNotFinish() {
        let runner = LocalCommandRunner()
        let result = runner.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "sleep 2"],
            environment: nil,
            timeout: 0.05
        )

        #expect(result.timedOut)
    }
}
