import Foundation

enum Logging {
    static func debug(_ message: String) {
#if DEBUG
        print("[PromptImprover] \(message)")
#endif
    }
}
