import Foundation
import os

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
        cachedCapabilities(for: tool, executableURL: executableURL, versionString: versionString)?.capabilities
    }

    func cachedCapabilities(
        for tool: Tool,
        executableURL: URL,
        versionString: String?,
        forceRefresh: Bool = false
    ) -> CachedToolCapabilities? {
        guard let signature = detector.makeSignature(tool: tool, executableURL: executableURL, versionString: versionString) else {
            return nil
        }

        var cache = loadCache()
        if !forceRefresh,
           let cached = cache.byTool[tool],
           cached.signature.matchesIdentity(of: signature) {
            return cached
        }

        let recomputed = detector.detectCapabilities(tool: tool, executableURL: executableURL, signature: signature)
        let updated = CachedToolCapabilities(signature: signature, capabilities: recomputed)
        cache.byTool[tool] = updated
        loadedCache = cache

        do {
            try persist(cache)
        } catch {
            StorageLogger.logger.error("Failed saving CLI discovery cache. error=\(error.localizedDescription)")
        }

        return updated
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        AppStorageLayout.bestEffort(fileManager: fileManager).cliDiscoveryCacheFile
    }

    private func loadCache() -> ToolCapabilityCache {
        if let loadedCache {
            return loadedCache
        }

        let cache: ToolCapabilityCache
        do {
            let data = try Data(contentsOf: fileURL)
            cache = try decodeCache(from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            cache = ToolCapabilityCache()
        } catch {
            StorageLogger.logger.error("Failed loading CLI discovery cache; cache will be rebuilt. error=\(error.localizedDescription)")
            cache = ToolCapabilityCache()
        }

        loadedCache = cache
        return cache
    }

    private func decodeCache(from data: Data) throws -> ToolCapabilityCache {
        let versioned = try decoder.decode(VersionedCapabilityCacheDocument.self, from: data)
        return ToolCapabilityCache(byTool: decodeToolMap(versioned.cacheByTool))
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

}

private struct VersionedCapabilityCacheDocument: Codable {
    let schemaVersion: Int
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
