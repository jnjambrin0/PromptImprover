import Foundation
import Darwin

enum ProcessOutput {
    case stdout(Data)
    case stderr(Data)
    case exit(Int32)
}

final class ProcessRunner {
    private let stateQueue = DispatchQueue(label: "PromptImprover.ProcessRunner")
    private var process: Process?
    private var timeoutTask: Task<Void, Never>?
    private var isFinished = false

    func run(
        executableURL: URL,
        arguments: [String],
        cwd: URL,
        env: [String: String],
        stdinData: Data? = nil,
        timeout: TimeInterval = 120
    ) -> AsyncThrowingStream<ProcessOutput, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = cwd
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = stdinPipe

            var mergedEnvironment = ProcessInfo.processInfo.environment
            env.forEach { mergedEnvironment[$0.key] = $0.value }
            process.environment = mergedEnvironment

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    continuation.yield(.stdout(data))
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    continuation.yield(.stderr(data))
                }
            }

            process.terminationHandler = { [weak self] terminated in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                self?.finishIfNeeded {
                    let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    if !remainingStdout.isEmpty {
                        continuation.yield(.stdout(remainingStdout))
                    }

                    let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    if !remainingStderr.isEmpty {
                        continuation.yield(.stderr(remainingStderr))
                    }

                    continuation.yield(.exit(terminated.terminationStatus))
                    continuation.finish()
                }
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                finishIfNeeded {
                    continuation.finish(throwing: PromptImproverError.processLaunchFailed(error.localizedDescription))
                }
                return
            }

            if let stdinData {
                stdinPipe.fileHandleForWriting.write(stdinData)
            }
            stdinPipe.fileHandleForWriting.closeFile()

            storeProcess(process)
            setupTimeout(seconds: timeout, continuation: continuation)

            continuation.onTermination = { [weak self] reason in
                switch reason {
                case .cancelled:
                    self?.cancel()
                case .finished:
                    break
                @unknown default:
                    self?.cancel()
                }
            }
        }
    }

    func cancel() {
        stateQueue.sync {
            guard let process, process.isRunning else {
                return
            }

            process.terminate()
            let pid = process.processIdentifier

            Task.detached {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if kill(pid, 0) == 0 {
                    kill(pid, SIGKILL)
                }
            }
        }
    }

    private func setupTimeout(seconds: TimeInterval, continuation: AsyncThrowingStream<ProcessOutput, Error>.Continuation) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            let nanos = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard let self else { return }

            var shouldTimeout = false
            self.stateQueue.sync {
                if !self.isFinished {
                    shouldTimeout = true
                }
            }

            if shouldTimeout {
                self.cancel()
                self.finishIfNeeded {
                    continuation.finish(throwing: PromptImproverError.processTimedOut(seconds: seconds))
                }
            }
        }
    }

    private func storeProcess(_ process: Process) {
        stateQueue.sync {
            self.process = process
            self.isFinished = false
        }
    }

    private func finishIfNeeded(_ body: () -> Void) {
        stateQueue.sync {
            guard !isFinished else {
                return
            }
            isFinished = true
            timeoutTask?.cancel()
            timeoutTask = nil
            process = nil
            body()
        }
    }
}
