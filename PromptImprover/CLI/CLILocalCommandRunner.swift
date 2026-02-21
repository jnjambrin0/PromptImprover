import Foundation
import Darwin

struct LocalCommandResult {
    let stdout: String
    let stderr: String
    let status: Int32
    let timedOut: Bool
    let launchErrorDescription: String?
}

protocol LocalCommandRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval
    ) -> LocalCommandResult
}

struct LocalCommandRunner: LocalCommandRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval
    ) -> LocalCommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var stdoutData = Data()
        var stderrData = Data()
        let lock = NSLock()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            lock.lock()
            stdoutData.append(data)
            lock.unlock()
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            lock.lock()
            stderrData.append(data)
            lock.unlock()
        }

        let terminationSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            return LocalCommandResult(
                stdout: "",
                stderr: "",
                status: -1,
                timedOut: false,
                launchErrorDescription: error.localizedDescription
            )
        }

        let timedOut = terminationSemaphore.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            terminate(process)
            _ = terminationSemaphore.wait(timeout: .now() + 0.5)
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        lock.lock()
        stdoutData.append(remainingStdout)
        stderrData.append(remainingStderr)
        let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        lock.unlock()

        return LocalCommandResult(
            stdout: stdoutText,
            stderr: stderrText,
            status: process.terminationStatus,
            timedOut: timedOut,
            launchErrorDescription: nil
        )
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else {
            return
        }

        process.terminate()
        let pid = process.processIdentifier
        usleep(150_000)
        if kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
    }
}
