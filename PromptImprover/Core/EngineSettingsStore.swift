import Foundation
import os

final class EngineSettingsStore {
    static let currentSchemaVersion = StorageSettingsDocument.currentSchemaVersion

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
            let document = try decoder.decode(StorageSettingsDocument.self, from: data)
            return EngineSettings(byTool: decodeToolMap(document.settingsByTool))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .default
        } catch {
            StorageLogger.logger.error("Failed loading settings. Falling back to defaults. error=\(error.localizedDescription)")
            return .default
        }
    }

    func save(_ settings: EngineSettings) throws {
        let document = StorageSettingsDocument(
            schemaVersion: EngineSettingsStore.currentSchemaVersion,
            settingsByTool: encodeToolMap(settings.byTool)
        )
        try jsonStore.encodeAndWrite(document, to: fileURL, using: encoder)
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        AppStorageLayout.bestEffort(fileManager: fileManager).settingsFile
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
