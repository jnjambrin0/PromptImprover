import Foundation
import os

final class GuidesCatalogStore {
    static let currentSchemaVersion = StorageModelMappingDocument.currentSchemaVersion

    private let fileURL: URL
    private let jsonStore: AtomicJSONStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL = GuidesCatalogStore.defaultFileURL(),
        jsonStore: AtomicJSONStore = AtomicJSONStore()
    ) {
        self.fileURL = fileURL
        self.jsonStore = jsonStore

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()
    }

    func load() -> GuidesCatalog {
        do {
            let data = try Data(contentsOf: fileURL)
            let document = try decoder.decode(StorageModelMappingDocument.self, from: data)
            return GuidesCatalog(outputModels: document.outputModels, guides: document.guides).reconciled()
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .default
        } catch {
            StorageLogger.logger.error("Failed loading model mapping. Falling back to defaults. error=\(error.localizedDescription)")
            return .default
        }
    }

    func save(_ catalog: GuidesCatalog) throws {
        let normalized = catalog.reconciled()
        let document = StorageModelMappingDocument(
            schemaVersion: GuidesCatalogStore.currentSchemaVersion,
            outputModels: normalized.outputModels,
            guides: normalized.guides
        )
        try jsonStore.encodeAndWrite(document, to: fileURL, using: encoder)
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        AppStorageLayout.bestEffort(fileManager: fileManager).modelMappingFile
    }
}
