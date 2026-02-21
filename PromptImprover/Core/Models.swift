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

struct RunRequest: Codable {
    let tool: Tool
    let targetSlug: String
    let targetDisplayName: String
    let mappedGuides: [GuideDoc]
    let inputPrompt: String
    let engineModel: String?
    let engineEffort: EngineEffort?

    init(
        tool: Tool,
        targetSlug: String,
        targetDisplayName: String,
        mappedGuides: [GuideDoc],
        inputPrompt: String,
        engineModel: String? = nil,
        engineEffort: EngineEffort? = nil
    ) {
        self.tool = tool
        self.targetSlug = targetSlug
        self.targetDisplayName = targetDisplayName
        self.mappedGuides = mappedGuides
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
