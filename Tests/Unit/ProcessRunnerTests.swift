import Foundation
import Testing
@testable import PromptImproverCore

@Suite(.serialized)
struct ProcessRunnerTests {
    @Test
    func capturesStdoutAndStderr() async throws {
        let runner = ProcessRunner()
        let stream = runner.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "printf 'out'; printf 'err' 1>&2"],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            env: [:],
            timeout: 5
        )

        var stdout = Data()
        var stderr = Data()
        var exitCode: Int32?

        for try await output in stream {
            switch output {
            case .stdout(let data):
                stdout.append(data)
            case .stderr(let data):
                stderr.append(data)
            case .exit(let code):
                exitCode = code
            }
        }

        #expect(String(decoding: stdout, as: UTF8.self).contains("out"))
        #expect(String(decoding: stderr, as: UTF8.self).contains("err"))
        #expect(exitCode == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func timeoutThrowsExpectedError() async {
        let runner = ProcessRunner()
        let timeoutScript = try! TestSupport.makeExecutableScript(
            name: "process-runner-timeout",
            script: "#!/bin/sh\nwhile true; do sleep 1; done\n",
            prefix: "ProcessRunner"
        )
        defer { TestSupport.removeItemIfPresent(timeoutScript.deletingLastPathComponent()) }

        let stream = runner.run(
            executableURL: timeoutScript,
            arguments: [],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            env: [:],
            timeout: 0.2
        )

        await #expect(throws: PromptImproverError.self) {
            for try await _ in stream { }
        }
    }

    @Test
    func cancelTerminatesProcess() async throws {
        let runner = ProcessRunner()
        let timeoutScript = try! TestSupport.makeExecutableScript(
            name: "process-runner-cancel",
            script: "#!/bin/sh\necho started\nwhile true; do sleep 1; done\n",
            prefix: "ProcessRunner"
        )
        defer { TestSupport.removeItemIfPresent(timeoutScript.deletingLastPathComponent()) }
        let stream = runner.run(
            executableURL: timeoutScript,
            arguments: [],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            env: [:],
            timeout: 15
        )

        let didStart = LockedFlag()
        let finished = Task {
            do {
                for try await output in stream {
                    if case .stdout(let data) = output,
                       String(decoding: data, as: UTF8.self).contains("started") {
                        didStart.setTrue()
                    }
                }
                return true
            } catch {
                return false
            }
        }

        #expect(await AsyncTestSupport.waitUntil(condition: { didStart.value }))
        runner.cancel()

        let didFinish = await finished.value
        #expect(didFinish)
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func setTrue() {
        lock.lock()
        flag = true
        lock.unlock()
    }
}
