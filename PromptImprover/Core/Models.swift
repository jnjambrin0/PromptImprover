import Foundation

enum Tool: String, CaseIterable, Identifiable, Codable {
    case codex
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex CLI"
        case .claude: return "Claude Code"
        }
    }

    var missingInstallMessage: String {
        switch self {
        case .codex:
            return "Install Codex CLI and ensure `codex` is accessible from your shell PATH."
        case .claude:
            return "Install Claude Code and ensure `claude` is accessible from your shell PATH."
        }
    }
}

enum TargetModel: String, CaseIterable, Identifiable, Codable {
    case claude46
    case gpt52
    case gemini30

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude46: return "Claude 4.6"
        case .gpt52: return "GPT-5.2"
        case .gemini30: return "Gemini 3.0"
        }
    }
}

struct RunRequest: Codable {
    let tool: Tool
    let targetModel: TargetModel
    let inputPrompt: String
    let engineModel: String?
    let engineEffort: EngineEffort?

    init(
        tool: Tool,
        targetModel: TargetModel,
        inputPrompt: String,
        engineModel: String? = nil,
        engineEffort: EngineEffort? = nil
    ) {
        self.tool = tool
        self.targetModel = targetModel
        self.inputPrompt = inputPrompt
        self.engineModel = engineModel
        self.engineEffort = engineEffort
    }
}

enum RunStatus: Equatable {
    case idle
    case running
    case done
    case error
    case cancelled
}

enum RunEvent {
    case delta(String)
    case completed(String)
    case failed(Error)
    case cancelled
}

struct CLIAvailability: Equatable {
    let tool: Tool
    let executableURL: URL?
    let installed: Bool
    let version: String?
    let healthMessage: String?
}
