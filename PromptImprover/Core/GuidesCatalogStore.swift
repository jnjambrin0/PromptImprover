import Foundation

final class GuidesCatalogStore {
    static let currentSchemaVersion = 1

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
            return decodeCatalog(from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .default
        } catch {
            Logging.debug("Failed loading guides catalog: \(error.localizedDescription)")
            return .default
        }
    }

    func save(_ catalog: GuidesCatalog) throws {
        let normalized = catalog.reconciled()
        let document = VersionedGuidesCatalogDocument(
            schemaVersion: GuidesCatalogStore.currentSchemaVersion,
            outputModels: normalized.outputModels,
            guides: normalized.guides
        )
        try jsonStore.encodeAndWrite(document, to: fileURL, using: encoder)
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        appSupportDirectory(fileManager: fileManager).appendingPathComponent("guides_catalog.json")
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

    private func decodeCatalog(from data: Data) -> GuidesCatalog {
        if let versioned = try? decoder.decode(VersionedGuidesCatalogDocument.self, from: data) {
            return GuidesCatalog(outputModels: versioned.outputModels, guides: versioned.guides)
        }

        if let legacyWrapped = try? decoder.decode(LegacyWrappedGuidesCatalogDocument.self, from: data) {
            return GuidesCatalog(outputModels: legacyWrapped.outputModels, guides: legacyWrapped.guides)
        }

        if let raw = try? decoder.decode(GuidesCatalog.self, from: data) {
            return raw.reconciled()
        }

        return .default
    }
}

private struct VersionedGuidesCatalogDocument: Codable {
    let schemaVersion: Int
    let outputModels: [OutputModel]
    let guides: [GuideDoc]
}

private struct LegacyWrappedGuidesCatalogDocument: Codable {
    let outputModels: [OutputModel]
    let guides: [GuideDoc]
}
