import Foundation

struct ToolBinarySignature: Codable, Equatable {
    let tool: Tool
    let path: String
    let versionString: String
    let mtime: TimeInterval
    let size: UInt64
    let lastCheckedAt: Date

    func matchesIdentity(of other: ToolBinarySignature) -> Bool {
        tool == other.tool
            && path == other.path
            && versionString == other.versionString
            && mtime == other.mtime
            && size == other.size
    }
}

struct ToolCapabilities: Codable, Equatable {
    let supportsModelFlag: Bool
    let supportsEffortConfig: Bool
    let supportedEffortValues: [EngineEffort]

    init(
        supportsModelFlag: Bool,
        supportsEffortConfig: Bool,
        supportedEffortValues: [EngineEffort]
    ) {
        self.supportsModelFlag = supportsModelFlag
        self.supportsEffortConfig = supportsEffortConfig
        self.supportedEffortValues = ToolEngineSettings.orderedUniqueEfforts(supportedEffortValues)
    }
}

struct CachedToolCapabilities: Codable, Equatable {
    let signature: ToolBinarySignature
    let capabilities: ToolCapabilities
}

struct ToolCapabilityCache: Codable, Equatable {
    var byTool: [Tool: CachedToolCapabilities]

    init(byTool: [Tool: CachedToolCapabilities] = [:]) {
        self.byTool = byTool
    }
}
