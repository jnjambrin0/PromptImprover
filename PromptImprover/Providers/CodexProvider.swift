import Foundation

final class CodexProvider: CLIProvider {
    private enum RunMode {
        case isolatedHome
        case inheritedHome
    }

    private let executableURL: URL
    private let processRunner: ProcessRunner
    private var activeTask: Task<Void, Never>?

    init(executableURL: URL, processRunner: ProcessRunner = ProcessRunner()) {
        self.executableURL = executableURL
        self.processRunner = processRunner
    }

    func run(request: RunRequest, workspace: WorkspaceHandle) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            activeTask = Task {
                do {
                    let optimized: String
                    do {
                        optimized = try await runAttempt(
                            request: request,
                            workspace: workspace,
                            mode: .isolatedHome
                        )
                    } catch {
                        if shouldRetryWithInheritedHome(for: error) {
                            optimized = try await runAttempt(
                                request: request,
                                workspace: workspace,
                                mode: .inheritedHome
                            )
                        } else {
                            throw error
                        }
                    }

                    continuation.yield(.completed(optimized))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.cancelled)
                    continuation.finish(throwing: PromptImproverError.cancelled)
                } catch {
                    continuation.yield(.failed(error))
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { [weak self] _ in
                self?.cancel()
            }
        }
    }

    func cancel() {
        processRunner.cancel()
        activeTask?.cancel()
        activeTask = nil
    }

    private func runAttempt(
        request: RunRequest,
        workspace: WorkspaceHandle,
        mode: RunMode
    ) async throws -> String {
        let finalOutputPath = workspace.path.appendingPathComponent("codex_output.json")
        let runPrompt = RunPromptBuilder.buildPrompt(
            for: request,
            guideFilenamesInOrder: workspace.guideFilenamesInOrder
        )
        let args = makeArguments(request: request, workspace: workspace, finalOutputPath: finalOutputPath)
        let env = makeEnvironment(workspace: workspace, mode: mode)

        let stream = processRunner.run(
            executableURL: executableURL,
            arguments: args,
            cwd: workspace.path,
            env: env,
            stdinData: runPrompt.data(using: .utf8),
            timeout: 120
        )

        var errorParser = CodexErrorJSONLParser()
        var stderrText = ""
        var stdoutErrors: [String] = []
        var terminated = false
        var exitCode: Int32 = 0

        for try await event in stream {
            switch event {
            case .stdout(let data):
                stdoutErrors.append(contentsOf: try errorParser.ingest(data))
            case .stderr(let data):
                if let text = String(data: data, encoding: .utf8) {
                    stderrText += text
                }
            case .exit(let code):
                terminated = true
                exitCode = code
            }
        }

        stdoutErrors.append(contentsOf: try errorParser.flush())

        let errorContext = mergedErrorContext(stderr: stderrText, stdoutErrors: stdoutErrors)
        if terminated && exitCode != 0 {
            throw classifyFailure(errorContext, fallback: "Codex execution failed.")
        }

        do {
            let finalData = try Data(contentsOf: finalOutputPath)
            return try OutputContract.normalizedOptimizedPrompt(from: finalData)
        } catch {
            if isAuthenticationFailureText(errorContext.lowercased()) {
                throw classifyFailure(errorContext, fallback: "Login from Terminal and retry.")
            }
            throw error
        }
    }

    private func makeArguments(request: RunRequest, workspace: WorkspaceHandle, finalOutputPath: URL) -> [String] {
        var arguments: [String] = [
            "exec",
            "--json",
            "--ephemeral",
            "--sandbox", "read-only",
            "--skip-git-repo-check",
            "--output-schema", workspace.schemaPath.path,
            "--output-last-message", finalOutputPath.path,
        ]

        if let model = request.engineModel?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }

        if let effort = request.engineEffort {
            arguments.append(contentsOf: ["-c", "model_reasoning_effort=\(effort.rawValue)"])
        }

        arguments.append(contentsOf: [
            "-C", workspace.path.path,
            "-"
        ])

        return arguments
    }

    private func makeEnvironment(workspace: WorkspaceHandle, mode: RunMode) -> [String: String] {
        let patchedPath = CLIExecutionEnvironment.patchedPATH(
            executableURL: executableURL,
            basePATH: ProcessInfo.processInfo.environment["PATH"]
        )

        switch mode {
        case .isolatedHome:
            let codexHomeURL = workspace.path.appendingPathComponent("codex_home", isDirectory: true)
            try? FileManager.default.createDirectory(at: codexHomeURL, withIntermediateDirectories: true)
            return [
                "CODEX_HOME": codexHomeURL.path,
                "PATH": patchedPath
            ]
        case .inheritedHome:
            return ["PATH": patchedPath]
        }
    }

    private func mergedErrorContext(stderr: String, stdoutErrors: [String]) -> String {
        var parts: [String] = []
        let stderrTrimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderrTrimmed.isEmpty {
            parts.append(stderrTrimmed)
        }
        let stdoutTrimmed = stdoutErrors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !stdoutTrimmed.isEmpty {
            parts.append(stdoutTrimmed.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n")
    }

    private func shouldRetryWithInheritedHome(for error: Error) -> Bool {
        if let appError = error as? PromptImproverError {
            switch appError {
            case .toolNotAuthenticated:
                return true
            case .toolExecutionFailed(let details):
                return isAuthenticationFailureText(details.lowercased())
            default:
                return false
            }
        }
        return isAuthenticationFailureText(error.localizedDescription.lowercased())
    }

    private func classifyFailure(_ details: String, fallback: String) -> PromptImproverError {
        let text = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        if isAuthenticationFailureText(lowered) {
            return .toolNotAuthenticated(text.isEmpty ? "Login from Terminal and retry." : text)
        }

        return .toolExecutionFailed(text.isEmpty ? fallback : text)
    }

    private func isAuthenticationFailureText(_ lowered: String) -> Bool {
        lowered.contains("unauthorized")
            || lowered.contains("missing bearer")
            || lowered.contains("api key")
            || lowered.contains("authentication")
            || lowered.contains("auth")
            || lowered.contains("login")
    }
}

private struct CodexErrorJSONLParser {
    private var lineBuffer = StreamLineBuffer()

    mutating func ingest(_ data: Data) throws -> [String] {
        let lines = try lineBuffer.append(data)
        return lines.compactMap(parseErrorMessage)
    }

    mutating func flush() throws -> [String] {
        guard let line = try lineBuffer.flushRemainder() else {
            return []
        }
        guard let parsed = parseErrorMessage(line) else {
            return []
        }
        return [parsed]
    }

    private func parseErrorMessage(_ line: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: line),
            let dict = object as? [String: Any],
            let type = dict["type"] as? String
        else {
            return nil
        }

        if type == "error", let message = dict["message"] as? String {
            return message
        }

        if type == "turn.failed",
           let error = dict["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        return nil
    }
}
