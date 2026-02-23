import Foundation

protocol ToolCapabilityDetecting {
    func makeSignature(tool: Tool, executableURL: URL, versionString: String?) -> ToolBinarySignature?
    func detectCapabilities(tool: Tool, executableURL: URL, signature: ToolBinarySignature) -> ToolCapabilities
}

struct ToolCapabilityDetector: ToolCapabilityDetecting {
    private let fileManager: FileManager
    private let localCommandRunner: LocalCommandRunning
    private let commandTimeout: TimeInterval

    init(
        fileManager: FileManager = .default,
        localCommandRunner: LocalCommandRunning = LocalCommandRunner(),
        commandTimeout: TimeInterval = 5
    ) {
        self.fileManager = fileManager
        self.localCommandRunner = localCommandRunner
        self.commandTimeout = commandTimeout
    }

    func makeSignature(tool: Tool, executableURL: URL, versionString: String?) -> ToolBinarySignature? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: executableURL.path)
        } catch {
            return nil
        }

        let mtimeDate = attributes[.modificationDate] as? Date
        let fileSize = attributes[.size] as? NSNumber
        let normalizedVersion = ToolCapabilityDetector.normalizedVersionString(from: versionString) ?? ""

        return ToolBinarySignature(
            tool: tool,
            path: executableURL.path,
            versionString: normalizedVersion,
            mtime: mtimeDate?.timeIntervalSince1970 ?? 0,
            size: fileSize?.uint64Value ?? 0,
            lastCheckedAt: Date()
        )
    }

    func detectCapabilities(tool: Tool, executableURL: URL, signature: ToolBinarySignature) -> ToolCapabilities {
        let helpText: String
        switch tool {
        case .codex:
            helpText = readHelpOutput(executableURL: executableURL, arguments: ["exec", "--help"])
        case .claude:
            helpText = readHelpOutput(executableURL: executableURL, arguments: ["--help"])
        }

        let supportsModelFlag = ToolCapabilityDetector.containsModelFlag(in: helpText)
        let lowerHelp = helpText.lowercased()

        switch tool {
        case .claude:
            return detectClaudeCapabilities(supportsModelFlag: supportsModelFlag, lowerHelp: lowerHelp)
        case .codex:
            return detectCodexCapabilities(
                supportsModelFlag: supportsModelFlag,
                lowerHelp: lowerHelp,
                versionString: signature.versionString
            )
        }
    }

    private func detectClaudeCapabilities(supportsModelFlag: Bool, lowerHelp: String) -> ToolCapabilities {
        let hasEffortFlag = lowerHelp.contains("--effort")
        let parsedValues = ToolCapabilityDetector.extractEffortValues(from: lowerHelp, for: .claude)
        let supportedValues = parsedValues.isEmpty ? EngineSettingsDefaults.defaultSupportedEfforts(for: .claude) : parsedValues

        return ToolCapabilities(
            supportsModelFlag: supportsModelFlag,
            supportsEffortConfig: hasEffortFlag,
            supportedEffortValues: hasEffortFlag ? supportedValues : []
        )
    }

    private func detectCodexCapabilities(
        supportsModelFlag: Bool,
        lowerHelp: String,
        versionString: String
    ) -> ToolCapabilities {
        let hasExplicitEffortSignal = lowerHelp.contains("model_reasoning_effort")
            || lowerHelp.contains("reasoning_effort")

        let parsedValues = ToolCapabilityDetector.extractEffortValues(from: lowerHelp, for: .codex)
        if hasExplicitEffortSignal {
            return ToolCapabilities(
                supportsModelFlag: supportsModelFlag,
                supportsEffortConfig: true,
                supportedEffortValues: parsedValues.isEmpty
                    ? EngineSettingsDefaults.defaultSupportedEfforts(for: .codex)
                    : parsedValues
            )
        }

        if ToolCapabilityDetector.supportsCodexEffortViaVersionMap(versionString: versionString) {
            return ToolCapabilities(
                supportsModelFlag: supportsModelFlag,
                supportsEffortConfig: true,
                supportedEffortValues: EngineSettingsDefaults.defaultSupportedEfforts(for: .codex)
            )
        }

        return ToolCapabilities(
            supportsModelFlag: supportsModelFlag,
            supportsEffortConfig: false,
            supportedEffortValues: []
        )
    }

    private func readHelpOutput(executableURL: URL, arguments: [String]) -> String {
        let output = runLocalCommand(executableURL: executableURL, arguments: arguments)
        return (output.stdout + "\n" + output.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runLocalCommand(executableURL: URL, arguments: [String]) -> (stdout: String, stderr: String, status: Int32) {
        let result = localCommandRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            environment: CLIExecutionEnvironment.environmentForExecutable(
                executableURL: executableURL,
                baseEnv: ProcessInfo.processInfo.environment
            ),
            timeout: commandTimeout
        )

        if let launchErrorDescription = result.launchErrorDescription {
            Logging.debug("Capability command failed to launch: \(launchErrorDescription)")
            return ("", "", -1)
        }

        if result.timedOut {
            Logging.debug("Capability command timed out for \(executableURL.lastPathComponent)")
            return ("", "", -1)
        }

        return (result.stdout, result.stderr, result.status)
    }

    private static func containsModelFlag(in helpText: String) -> Bool {
        let lowered = helpText.lowercased()
        return lowered.contains("--model") || lowered.contains("-m, --model")
    }

    private static func extractEffortValues(from text: String, for tool: Tool) -> [EngineEffort] {
        var ordered: [EngineEffort] = []
        for effort in EngineSettingsDefaults.defaultSupportedEfforts(for: tool) {
            if text.range(of: effort.rawValue, options: [.caseInsensitive]) != nil {
                ordered.append(effort)
            }
        }
        return ToolEngineSettings.orderedUniqueEfforts(ordered)
    }

    private static func normalizedVersionString(from raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func supportsCodexEffortViaVersionMap(versionString: String) -> Bool {
        guard let version = SemanticVersion.parse(from: versionString) else {
            return false
        }
        return version >= SemanticVersion(major: 0, minor: 104, patch: 0)
    }
}

private struct SemanticVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }

    static func parse(from text: String) -> SemanticVersion? {
        let pattern = #"(\d+)\.(\d+)\.(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges == 4 else {
            return nil
        }

        guard
            let majorRange = Range(match.range(at: 1), in: text),
            let minorRange = Range(match.range(at: 2), in: text),
            let patchRange = Range(match.range(at: 3), in: text),
            let major = Int(text[majorRange]),
            let minor = Int(text[minorRange]),
            let patch = Int(text[patchRange])
        else {
            return nil
        }

        return SemanticVersion(major: major, minor: minor, patch: patch)
    }
}
