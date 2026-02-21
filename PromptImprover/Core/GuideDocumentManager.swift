import CryptoKit
import Foundation

protocol GuideDocumentManaging {
    func importGuide(from sourceURL: URL) throws -> GuideDoc
    func data(for guide: GuideDoc) throws -> Data
    func deleteUserGuideFileIfPresent(for guide: GuideDoc) throws
}

final class GuideDocumentManager: GuideDocumentManaging {
    private let fileManager: FileManager
    private let templates: Templates
    private let appSupportDirectory: URL
    private let maxImportSizeBytes: Int

    init(
        fileManager: FileManager = .default,
        templates: Templates = Templates(),
        appSupportDirectory: URL? = nil,
        maxImportSizeBytes: Int = 1_048_576
    ) {
        self.fileManager = fileManager
        self.templates = templates
        self.maxImportSizeBytes = maxImportSizeBytes
        self.appSupportDirectory = appSupportDirectory ?? GuideDocumentManager.defaultAppSupportDirectory(fileManager: fileManager)
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
        let relativeStoragePath = "guides/\(guideID).md"
        let absoluteURL = appSupportDirectory.appendingPathComponent(relativeStoragePath)
        try fileManager.createDirectory(at: absoluteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: absoluteURL, options: .atomic)

        let title = sourceURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = "Imported Guide"
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

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
            return try templates.data(forRelativePath: guide.storagePath)
        }

        let userURL = try userGuideAbsoluteURL(forStoragePath: guide.storagePath)
        guard fileManager.fileExists(atPath: userURL.path) else {
            throw PromptImproverError.guideManagementFailed("Missing guide document at \(guide.storagePath).")
        }

        return try Data(contentsOf: userURL)
    }

    func deleteUserGuideFileIfPresent(for guide: GuideDoc) throws {
        guard !guide.isBuiltIn else {
            return
        }

        let userURL = try userGuideAbsoluteURL(forStoragePath: guide.storagePath)
        guard fileManager.fileExists(atPath: userURL.path) else {
            return
        }

        try fileManager.removeItem(at: userURL)
    }

    private func userGuideAbsoluteURL(forStoragePath storagePath: String) throws -> URL {
        guard let normalized = GuideDoc.normalizeStoragePath(storagePath),
              !normalized.hasPrefix("/"),
              !normalized.contains("..") else {
            throw PromptImproverError.guideManagementFailed("Invalid guide storage path.")
        }

        return appSupportDirectory.appendingPathComponent(normalized)
    }

    private static func defaultAppSupportDirectory(fileManager: FileManager) -> URL {
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
