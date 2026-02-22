import Foundation
import Testing
@testable import PromptImproverCore

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

    @Test
    func timeoutThrowsExpectedError() async {
        let runner = ProcessRunner()
        let stream = runner.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "sleep 2"],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            env: [:],
            timeout: 0.2
        )

        do {
            for try await _ in stream { }
            Issue.record("Expected timeout error")
        } catch {
            guard case PromptImproverError.processTimedOut = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test
    func cancelTerminatesProcess() async throws {
        let runner = ProcessRunner()
        let stream = runner.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "sleep 10"],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            env: [:],
            timeout: 15
        )

        let finished = Task {
            do {
                for try await _ in stream { }
                return true
            } catch {
                return false
            }
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        runner.cancel()

        let didFinish = await finished.value
        #expect(didFinish)
    }
}
