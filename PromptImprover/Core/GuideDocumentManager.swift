import CryptoKit
import Foundation

protocol GuideDocumentManaging {
    func importGuide(from sourceURL: URL) throws -> GuideDoc
    func data(for guide: GuideDoc) throws -> Data
    func loadText(for guide: GuideDoc) throws -> String
    func ensureEditableGuide(_ guide: GuideDoc) throws -> GuideDoc
    func saveText(_ text: String, for guide: GuideDoc) throws -> GuideDoc
    func revertBuiltInFork(for guide: GuideDoc) throws -> GuideDoc
    func hasFork(for guide: GuideDoc) -> Bool
    func deleteUserGuideFileIfPresent(for guide: GuideDoc) throws
}

final class GuideDocumentManager: GuideDocumentManaging {
    private let fileManager: FileManager
    private let templates: Templates
    private let storageLayout: AppStorageLayout
    private let maxImportSizeBytes: Int
    private let atomicFileStore: AtomicJSONStore

    init(
        fileManager: FileManager = .default,
        templates: Templates = Templates(),
        storageLayout: AppStorageLayout? = nil,
        maxImportSizeBytes: Int = 1_048_576,
        atomicFileStore: AtomicJSONStore? = nil
    ) {
        self.fileManager = fileManager
        self.templates = templates
        self.maxImportSizeBytes = maxImportSizeBytes
        self.storageLayout = storageLayout ?? AppStorageLayout.bestEffort(fileManager: fileManager)
        self.atomicFileStore = atomicFileStore ?? AtomicJSONStore(fileManager: fileManager)
    }

    func importGuide(from sourceURL: URL) throws -> GuideDoc {
        guard sourceURL.pathExtension.caseInsensitiveCompare("md") == .orderedSame else {
            throw PromptImproverError.guideImportFailed("Only Markdown (.md) files can be imported.")
        }

        let data = try Data(contentsOf: sourceURL)
        guard data.count <= maxImportSizeBytes else {
            throw PromptImproverError.guideImportFailed("Guide exceeds maximum size of \(maxImportSizeBytes) bytes.")
        }

        guard String(data: data, encoding: .utf8) != nil else {
            throw PromptImproverError.guideImportFailed("Guide must be valid UTF-8 text.")
        }

        let guideID = "guide-\(UUID().uuidString.lowercased())"
        let relativeStoragePath = "guides/user/\(guideID).md"
        let absoluteURL = try absoluteURL(forStoragePath: relativeStoragePath)
        try atomicFileStore.write(data, to: absoluteURL)

        let title = sourceURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = "Imported Guide"
        let hash = sha256Hex(data)

        return GuideDoc(
            id: guideID,
            title: title.isEmpty ? fallbackTitle : title,
            storagePath: relativeStoragePath,
            isBuiltIn: false,
            updatedAt: Date(),
            hash: hash
        )
    }

    func data(for guide: GuideDoc) throws -> Data {
        if guide.isBuiltIn {
            if let forkURL = resolvedBuiltInForkAbsoluteURL(for: guide) {
                return try Data(contentsOf: forkURL)
            }

            let templateRelativePath = builtInTemplateRelativePath(for: guide)
            do {
                return try templates.data(forRelativePath: templateRelativePath)
            } catch {
                throw PromptImproverError.guideManagementFailed("Missing built-in guide template at \(templateRelativePath).")
            }
        }

        let userURL = try absoluteURL(forStoragePath: guide.storagePath)
        guard fileManager.fileExists(atPath: userURL.path) else {
            throw PromptImproverError.guideManagementFailed("Missing guide document at \(guide.storagePath).")
        }

        return try Data(contentsOf: userURL)
    }

    func loadText(for guide: GuideDoc) throws -> String {
        let loadedData = try data(for: guide)
        guard let text = String(data: loadedData, encoding: .utf8) else {
            throw PromptImproverError.guideManagementFailed("Guide must be valid UTF-8 text.")
        }
        return text
    }

    func ensureEditableGuide(_ guide: GuideDoc) throws -> GuideDoc {
        guard guide.isBuiltIn else {
            return guide
        }

        if hasFork(for: guide) {
            return guide
        }

        let forkStoragePath = GuideDoc.normalizeStoragePath(guide.forkStoragePath) ?? defaultForkStoragePath(forGuideID: guide.id)
        let forkURL = try absoluteURL(forStoragePath: forkStoragePath)
        let builtInData = try data(for: guide)
        try atomicFileStore.write(builtInData, to: forkURL)

        var editable = guide
        editable.forkStoragePath = forkStoragePath
        editable.hash = sha256Hex(builtInData)
        return editable
    }

    func saveText(_ text: String, for guide: GuideDoc) throws -> GuideDoc {
        guard let contentData = text.data(using: .utf8) else {
            throw PromptImproverError.guideManagementFailed("Guide must be valid UTF-8 text.")
        }

        var updatedGuide = guide
        if guide.isBuiltIn {
            updatedGuide = try ensureEditableGuide(guide)
            guard let forkStoragePath = GuideDoc.normalizeStoragePath(updatedGuide.forkStoragePath) else {
                throw PromptImproverError.guideManagementFailed("Guide fork path is invalid.")
            }

            let forkURL = try absoluteURL(forStoragePath: forkStoragePath)
            try atomicFileStore.write(contentData, to: forkURL)
        } else {
            let userURL = try absoluteURL(forStoragePath: updatedGuide.storagePath)
            try atomicFileStore.write(contentData, to: userURL)
        }

        updatedGuide.updatedAt = Date()
        updatedGuide.hash = sha256Hex(contentData)
        return updatedGuide
    }

    func revertBuiltInFork(for guide: GuideDoc) throws -> GuideDoc {
        guard guide.isBuiltIn else {
            throw PromptImproverError.guideManagementFailed("Only built-in guides can be reverted.")
        }

        if let forkStoragePath = GuideDoc.normalizeStoragePath(guide.forkStoragePath),
           let forkURL = try? absoluteURL(forStoragePath: forkStoragePath),
           fileManager.fileExists(atPath: forkURL.path) {
            try fileManager.removeItem(at: forkURL)
        }

        var reverted = guide
        reverted.forkStoragePath = nil
        reverted.updatedAt = Date()
        reverted.hash = nil
        return reverted
    }

    func hasFork(for guide: GuideDoc) -> Bool {
        guard let forkURL = resolvedBuiltInForkAbsoluteURL(for: guide) else {
            return false
        }
        return fileManager.fileExists(atPath: forkURL.path)
    }

    func deleteUserGuideFileIfPresent(for guide: GuideDoc) throws {
        guard !guide.isBuiltIn else {
            return
        }

        let userURL = try absoluteURL(forStoragePath: guide.storagePath)
        guard fileManager.fileExists(atPath: userURL.path) else {
            return
        }

        try fileManager.removeItem(at: userURL)
    }

    private func resolvedBuiltInForkAbsoluteURL(for guide: GuideDoc) -> URL? {
        guard guide.isBuiltIn,
              let forkStoragePath = GuideDoc.normalizeStoragePath(guide.forkStoragePath),
              let forkURL = try? absoluteURL(forStoragePath: forkStoragePath),
              fileManager.fileExists(atPath: forkURL.path) else {
            return nil
        }

        return forkURL
    }

    private func defaultForkStoragePath(forGuideID guideID: String) -> String {
        let safeID = sanitizedFilenameComponent(guideID)
        return "guides/user/forks/\(safeID).md"
    }

    private func sanitizedFilenameComponent(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let replaced = lowered.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return "-"
        }

        var normalized = String(replaced)
        normalized = normalized.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return normalized.isEmpty ? "guide" : normalized
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func absoluteURL(forStoragePath storagePath: String) throws -> URL {
        guard let normalized = GuideDoc.normalizeStoragePath(storagePath),
              !normalized.hasPrefix("/"),
              !normalized.contains("..") else {
            throw PromptImproverError.guideManagementFailed("Invalid guide storage path.")
        }

        return storageLayout.appSupportRoot.appendingPathComponent(normalized)
    }

    private func builtInTemplateRelativePath(for guide: GuideDoc) -> String {
        if let mapped = GuidesDefaults.builtInTemplateRelativePath(forGuideID: guide.id) {
            return mapped
        }

        let normalized = GuideDoc.normalizeStoragePath(guide.storagePath) ?? guide.storagePath
        return URL(fileURLWithPath: normalized).lastPathComponent
    }
}
