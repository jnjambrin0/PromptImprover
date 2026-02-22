import Foundation
import os

enum StorageLogger {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PromptImprover",
        category: "storage"
    )
}
