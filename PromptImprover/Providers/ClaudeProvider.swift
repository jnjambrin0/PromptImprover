import Foundation

final class ClaudeProvider: CLIProvider {
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
                    let optimized = try await runStreamingThenResolve(
                        request: request,
                        workspace: workspace,
                        continuation: continuation
                    )
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

    private func runStreamingThenResolve(
        request: RunRequest,
        workspace: WorkspaceHandle,
        continuation: AsyncThrowingStream<RunEvent, Error>.Continuation
    ) async throws -> String {
        let runPrompt = RunPromptBuilder.buildPrompt(for: request)
        var args = [
            "-p", runPrompt,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--permission-mode", "dontAsk"
        ]
        if let model = request.engineModel?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            args.append(contentsOf: ["--model", model])
        }

        let env = makeEnvironment()

        let stream = processRunner.run(
            executableURL: executableURL,
            arguments: args,
            cwd: workspace.path,
            env: env,
            timeout: 120
        )

        var parser = ClaudeStreamJSONParser()
        var rawStdout = Data()
        var rawStderr = Data()
        var terminated = false
        var exitCode: Int32 = 0

        for try await event in stream {
            switch event {
            case .stdout(let data):
                rawStdout.append(data)
                let deltas = try parser.ingest(data)
                deltas.forEach { continuation.yield(.delta($0)) }
            case .stderr(let data):
                rawStderr.append(data)
            case .exit(let code):
                terminated = true
                exitCode = code
            }
        }

        _ = try parser.flush()

        if terminated && exitCode != 0 {
            throw classifyFailure(rawStderr)
        }

        if let optimized = try extractOptimizedPromptFromStream(rawStdout) {
            return optimized
        }

        return try await fallbackJSONRun(request: request, workspace: workspace)
    }

    private func fallbackJSONRun(request: RunRequest, workspace: WorkspaceHandle) async throws -> String {
        let runPrompt = RunPromptBuilder.buildPrompt(for: request)
        let schemaString = try String(contentsOf: workspace.schemaPath, encoding: .utf8)

        var args = [
            "-p", runPrompt,
            "--output-format", "json",
            "--json-schema", schemaString,
            "--permission-mode", "dontAsk"
        ]
        if let model = request.engineModel?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            args.append(contentsOf: ["--model", model])
        }

        let env = makeEnvironment()

        let stream = processRunner.run(
            executableURL: executableURL,
            arguments: args,
            cwd: workspace.path,
            env: env,
            timeout: 120
        )

        var stdout = Data()
        var stderr = Data()
        var exitCode: Int32 = 0

        for try await event in stream {
            switch event {
            case .stdout(let data):
                stdout.append(data)
            case .stderr(let data):
                stderr.append(data)
            case .exit(let code):
                exitCode = code
            }
        }

        if exitCode != 0 {
            throw classifyFailure(stderr)
        }

        guard let optimized = try extractOptimizedPromptFromJSON(stdout) else {
            throw PromptImproverError.schemaMismatch
        }

        return optimized
    }

    private func extractOptimizedPromptFromStream(_ data: Data) throws -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) {
            if let dict = object as? [String: Any], let candidate = extractPromptCandidate(from: dict) {
                return candidate
            }
            if let direct = try? OutputContract.normalizedOptimizedPrompt(from: object) {
                return direct
            }
        }

        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        for line in text.split(separator: "\n") {
            guard
                let lineData = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: lineData),
                let dict = object as? [String: Any],
                let type = dict["type"] as? String
            else {
                continue
            }

            if type == "result", let candidate = extractPromptCandidate(from: dict) {
                return candidate
            }

            if let structured = dict["structured_output"],
               let candidate = try? OutputContract.normalizedOptimizedPrompt(from: structured) {
                return candidate
            }
        }

        if let regexMatch = parseOptimizedPromptByRegex(text),
           let normalized = try? OutputContract.normalizePrompt(regexMatch) {
            return normalized
        }

        return nil
    }

    private func extractOptimizedPromptFromJSON(_ data: Data) throws -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) {
            if let dict = object as? [String: Any], let candidate = extractPromptCandidate(from: dict) {
                return candidate
            }
            if let direct = try? OutputContract.normalizedOptimizedPrompt(from: object) {
                return direct
            }
        }

        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        for line in text.split(separator: "\n") {
            guard
                let lineData = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: lineData),
                let dict = object as? [String: Any]
            else {
                continue
            }

            if let candidate = extractPromptCandidate(from: dict) {
                return candidate
            }
        }

        if let regexMatch = parseOptimizedPromptByRegex(text),
           let normalized = try? OutputContract.normalizePrompt(regexMatch) {
            return normalized
        }

        return nil
    }

    private func extractPromptCandidate(from dict: [String: Any]) -> String? {
        if let structured = dict["structured_output"],
           let normalized = try? OutputContract.normalizedOptimizedPrompt(from: structured) {
            return normalized
        }

        if let resultText = dict["result"] as? String {
            if let resultData = resultText.data(using: .utf8),
               let resultObject = try? JSONSerialization.jsonObject(with: resultData),
               let normalized = try? OutputContract.normalizedOptimizedPrompt(from: resultObject) {
                return normalized
            }
            if let regexMatch = parseOptimizedPromptByRegex(resultText),
               let normalized = try? OutputContract.normalizePrompt(regexMatch) {
                return normalized
            }
        }

        return nil
    }

    private func parseOptimizedPromptByRegex(_ text: String) -> String? {
        let pattern = "\"optimized_prompt\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else {
            return nil
        }

        guard let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let escapedValue = String(text[captureRange])
        let quoted = "\"" + escapedValue + "\""
        guard
            let quotedData = quoted.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(String.self, from: quotedData)
        else {
            return escapedValue
        }

        return decoded
    }

    private func classifyFailure(_ stderrData: Data) -> PromptImproverError {
        let message = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lowered = message.lowercased()

        if lowered.contains("login") || lowered.contains("auth") || lowered.contains("unauthorized") {
            return .toolNotAuthenticated(message)
        }

        return .toolExecutionFailed(message.isEmpty ? "Claude execution failed." : message)
    }

    private func makeEnvironment() -> [String: String] {
        [
            "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
            "CLAUDE_CODE_DISABLE_BACKGROUND_TASKS": "1",
            "PATH": CLIExecutionEnvironment.patchedPATH(
                executableURL: executableURL,
                basePATH: ProcessInfo.processInfo.environment["PATH"]
            )
        ]
    }
}
