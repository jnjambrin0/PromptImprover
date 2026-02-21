import Foundation

final class ToolCapabilityCacheStore {
    static let currentSchemaVersion = 1

    private let fileURL: URL
    private let jsonStore: AtomicJSONStore
    private let detector: ToolCapabilityDetecting
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var loadedCache: ToolCapabilityCache?

    init(
        fileURL: URL = ToolCapabilityCacheStore.defaultFileURL(),
        detector: ToolCapabilityDetecting = ToolCapabilityDetector(),
        jsonStore: AtomicJSONStore = AtomicJSONStore()
    ) {
        self.fileURL = fileURL
        self.detector = detector
        self.jsonStore = jsonStore

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()
    }

    func capabilities(for tool: Tool, executableURL: URL, versionString: String?) -> ToolCapabilities? {
        guard let signature = detector.makeSignature(tool: tool, executableURL: executableURL, versionString: versionString) else {
            return nil
        }

        var cache = loadCache()
        if let cached = cache.byTool[tool], cached.signature.matchesIdentity(of: signature) {
            return cached.capabilities
        }

        let recomputed = detector.detectCapabilities(tool: tool, executableURL: executableURL, signature: signature)
        cache.byTool[tool] = CachedToolCapabilities(signature: signature, capabilities: recomputed)
        loadedCache = cache

        do {
            try persist(cache)
        } catch {
            Logging.debug("Failed saving capability cache: \(error.localizedDescription)")
        }

        return recomputed
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        appSupportDirectory(fileManager: fileManager).appendingPathComponent("tool_capabilities.json")
    }

    private func loadCache() -> ToolCapabilityCache {
        if let loadedCache {
            return loadedCache
        }

        let cache: ToolCapabilityCache
        do {
            let data = try Data(contentsOf: fileURL)
            cache = decodeCache(from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            cache = ToolCapabilityCache()
        } catch {
            Logging.debug("Failed loading capability cache: \(error.localizedDescription)")
            cache = ToolCapabilityCache()
        }

        loadedCache = cache
        return cache
    }

    private func decodeCache(from data: Data) -> ToolCapabilityCache {
        if let versioned = try? decoder.decode(VersionedCapabilityCacheDocument.self, from: data) {
            return ToolCapabilityCache(byTool: decodeToolMap(versioned.cacheByTool))
        }

        if let legacyWrapped = try? decoder.decode(LegacyWrappedCapabilityCacheDocument.self, from: data) {
            return ToolCapabilityCache(byTool: decodeToolMap(legacyWrapped.cacheByTool))
        }

        if let legacyRaw = try? decoder.decode([String: CachedToolCapabilities].self, from: data) {
            return ToolCapabilityCache(byTool: decodeLegacyToolMap(legacyRaw))
        }

        return ToolCapabilityCache()
    }

    private func persist(_ cache: ToolCapabilityCache) throws {
        let document = VersionedCapabilityCacheDocument(
            schemaVersion: ToolCapabilityCacheStore.currentSchemaVersion,
            cacheByTool: encodeToolMap(cache.byTool)
        )
        try jsonStore.encodeAndWrite(document, to: fileURL, using: encoder)
    }

    private func decodeToolMap(_ rawMap: [String: StoredCapabilityEntry]) -> [Tool: CachedToolCapabilities] {
        var decoded: [Tool: CachedToolCapabilities] = [:]
        for (rawTool, rawEntry) in rawMap {
            guard
                let tool = Tool(rawValue: rawTool),
                let signatureTool = Tool(rawValue: rawEntry.signature.tool)
            else {
                continue
            }

            let signature = ToolBinarySignature(
                tool: signatureTool,
                path: rawEntry.signature.path,
                versionString: rawEntry.signature.versionString,
                mtime: rawEntry.signature.mtime,
                size: rawEntry.signature.size,
                lastCheckedAt: rawEntry.signature.lastCheckedAt
            )
            decoded[tool] = CachedToolCapabilities(
                signature: signature,
                capabilities: rawEntry.capabilities
            )
        }
        return decoded
    }

    private func encodeToolMap(_ map: [Tool: CachedToolCapabilities]) -> [String: StoredCapabilityEntry] {
        var encoded: [String: StoredCapabilityEntry] = [:]
        for (tool, cachedEntry) in map {
            encoded[tool.rawValue] = StoredCapabilityEntry(
                signature: StoredToolBinarySignature(
                    tool: cachedEntry.signature.tool.rawValue,
                    path: cachedEntry.signature.path,
                    versionString: cachedEntry.signature.versionString,
                    mtime: cachedEntry.signature.mtime,
                    size: cachedEntry.signature.size,
                    lastCheckedAt: cachedEntry.signature.lastCheckedAt
                ),
                capabilities: cachedEntry.capabilities
            )
        }
        return encoded
    }

    private func decodeLegacyToolMap(_ rawMap: [String: CachedToolCapabilities]) -> [Tool: CachedToolCapabilities] {
        var decoded: [Tool: CachedToolCapabilities] = [:]
        for (rawTool, entry) in rawMap {
            guard let tool = Tool(rawValue: rawTool) else {
                continue
            }
            decoded[tool] = entry
        }
        return decoded
    }

    private static func appSupportDirectory(fileManager: FileManager) -> URL {
        if let directory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return directory.appendingPathComponent("PromptImprover", isDirectory: true)
        }

        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/PromptImprover", isDirectory: true)
    }
}

private struct VersionedCapabilityCacheDocument: Codable {
    let schemaVersion: Int
    let cacheByTool: [String: StoredCapabilityEntry]
}

private struct LegacyWrappedCapabilityCacheDocument: Codable {
    let cacheByTool: [String: StoredCapabilityEntry]
}

private struct StoredCapabilityEntry: Codable {
    let signature: StoredToolBinarySignature
    let capabilities: ToolCapabilities
}

private struct StoredToolBinarySignature: Codable {
    let tool: String
    let path: String
    let versionString: String
    let mtime: TimeInterval
    let size: UInt64
    let lastCheckedAt: Date
}
