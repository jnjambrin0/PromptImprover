import Foundation

final class EngineSettingsStore {
    static let currentSchemaVersion = 1

    private let fileURL: URL
    private let jsonStore: AtomicJSONStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL = EngineSettingsStore.defaultFileURL(),
        jsonStore: AtomicJSONStore = AtomicJSONStore()
    ) {
        self.fileURL = fileURL
        self.jsonStore = jsonStore

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()
    }

    func load() -> EngineSettings {
        do {
            let data = try Data(contentsOf: fileURL)
            return decodeSettings(from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .default
        } catch {
            Logging.debug("Failed loading engine settings: \(error.localizedDescription)")
            return .default
        }
    }

    func save(_ settings: EngineSettings) throws {
        let document = VersionedEngineSettingsDocument(
            schemaVersion: EngineSettingsStore.currentSchemaVersion,
            settingsByTool: encodeToolMap(settings.byTool)
        )
        try jsonStore.encodeAndWrite(document, to: fileURL, using: encoder)
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        appSupportDirectory(fileManager: fileManager).appendingPathComponent("engine_settings.json")
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

    private func decodeSettings(from data: Data) -> EngineSettings {
        if let versioned = try? decoder.decode(VersionedEngineSettingsDocument.self, from: data) {
            return EngineSettings(byTool: decodeToolMap(versioned.settingsByTool))
        }

        if let legacyWrapped = try? decoder.decode(LegacyWrappedEngineSettingsDocument.self, from: data) {
            return EngineSettings(byTool: decodeToolMap(legacyWrapped.settingsByTool))
        }

        if let legacyRaw = try? decoder.decode([String: ToolEngineSettings].self, from: data) {
            return EngineSettings(byTool: decodeToolMap(legacyRaw))
        }

        return .default
    }

    private func decodeToolMap(_ rawMap: [String: ToolEngineSettings]) -> [Tool: ToolEngineSettings] {
        var decoded: [Tool: ToolEngineSettings] = [:]
        for (rawTool, settings) in rawMap {
            guard let tool = Tool(rawValue: rawTool) else {
                continue
            }
            decoded[tool] = settings
        }
        return decoded
    }

    private func encodeToolMap(_ map: [Tool: ToolEngineSettings]) -> [String: ToolEngineSettings] {
        var encoded: [String: ToolEngineSettings] = [:]
        for (tool, settings) in map {
            encoded[tool.rawValue] = settings
        }
        return encoded
    }
}

private struct VersionedEngineSettingsDocument: Codable {
    let schemaVersion: Int
    let settingsByTool: [String: ToolEngineSettings]
}

private struct LegacyWrappedEngineSettingsDocument: Codable {
    let settingsByTool: [String: ToolEngineSettings]
}
