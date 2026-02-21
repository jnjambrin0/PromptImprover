import Foundation

enum PromptImproverError: LocalizedError {
    case toolNotInstalled(Tool)
    case toolExecutionFailed(String)
    case toolNotAuthenticated(String)
    case processLaunchFailed(String)
    case processTimedOut(seconds: TimeInterval)
    case cancelled
    case invalidOutput(String)
    case schemaMismatch
    case lineTooLong(limitBytes: Int)
    case bufferOverflow(limitBytes: Int)
    case workspaceFailure(String)

    var errorDescription: String? {
        switch self {
        case .toolNotInstalled:
            return "Install Codex CLI / Claude Code and ensure it’s accessible."
        case .toolExecutionFailed(let details):
            return details.isEmpty ? "Tool execution failed." : details
        case .toolNotAuthenticated(let details):
            if details.isEmpty {
                return "Login from Terminal and retry."
            }
            return details + "\nLogin from Terminal and retry."
        case .processLaunchFailed(let details):
            return details
        case .processTimedOut:
            return "Timed out. Try again."
        case .cancelled:
            return "Cancelled"
        case .invalidOutput:
            return "Tool returned invalid output (schema mismatch)."
        case .schemaMismatch:
            return "Tool returned invalid output (schema mismatch)."
        case .lineTooLong:
            return "Streaming parser exceeded max line size."
        case .bufferOverflow:
            return "Streaming parser exceeded max buffer size."
        case .workspaceFailure(let details):
            return details
        }
    }
}
