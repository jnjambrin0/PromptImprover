import Foundation
import Testing
@testable import PromptImproverCore

struct GuideDocumentManagerTests {
    @Test
    func rejectsNonMarkdownImports() throws {
        let context = try makeContext()
        let manager = context.makeManager(maxImportSizeBytes: 256)

        let sourceURL = context.sourcesDirectory.appendingPathComponent("not-markdown.txt")
        try Data("hello".utf8).write(to: sourceURL, options: .atomic)

        do {
            _ = try manager.importGuide(from: sourceURL)
            Issue.record("Expected markdown validation failure")
        } catch {
            guard case PromptImproverError.guideImportFailed = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test
    func rejectsOversizedImports() throws {
        let context = try makeContext()
        let manager = context.makeManager(maxImportSizeBytes: 16)

        let sourceURL = context.sourcesDirectory.appendingPathComponent("oversize.md")
        try Data(repeating: 0x61, count: 32).write(to: sourceURL, options: .atomic)

        do {
            _ = try manager.importGuide(from: sourceURL)
            Issue.record("Expected max-size validation failure")
        } catch {
            guard case PromptImproverError.guideImportFailed = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test
    func rejectsInvalidUTF8Imports() throws {
        let context = try makeContext()
        let manager = context.makeManager(maxImportSizeBytes: 256)

        let sourceURL = context.sourcesDirectory.appendingPathComponent("invalid.md")
        let invalidUTF8 = Data([0xC3, 0x28])
        try invalidUTF8.write(to: sourceURL, options: .atomic)

        do {
            _ = try manager.importGuide(from: sourceURL)
            Issue.record("Expected UTF-8 validation failure")
        } catch {
            guard case PromptImproverError.guideImportFailed = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test
    func importsMarkdownAndPersistsInAppSupport() throws {
        let context = try makeContext()
        let manager = context.makeManager(maxImportSizeBytes: 1_048_576)

        let sourceURL = context.sourcesDirectory.appendingPathComponent("my-guide.md")
        let body = "# Guide\n\nUse strict JSON output.\n"
        try Data(body.utf8).write(to: sourceURL, options: .atomic)

        let imported = try manager.importGuide(from: sourceURL)

        #expect(imported.isBuiltIn == false)
        #expect(imported.title == "my-guide")
        #expect(imported.storagePath.hasPrefix("guides/"))
        #expect(imported.storagePath.hasSuffix(".md"))
        #expect(imported.hash != nil)

        let importedData = try manager.data(for: imported)
        #expect(String(data: importedData, encoding: .utf8) == body)

        let absoluteURL = context.appSupportDirectory.appendingPathComponent(imported.storagePath)
        #expect(FileManager.default.fileExists(atPath: absoluteURL.path))

        try manager.deleteUserGuideFileIfPresent(for: imported)
        #expect(!FileManager.default.fileExists(atPath: absoluteURL.path))
    }

    @Test
    func resolvesBuiltInGuidesFromTemplates() throws {
        let context = try makeContext()
        let manager = context.makeManager(maxImportSizeBytes: 1_048_576)
        let guide = try #require(GuidesCatalog.default.guide(id: GuidesDefaults.gptGuideID))

        let data = try manager.data(for: guide)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("GPT-5.2"))
    }

    private func makeContext() throws -> GuideManagerTestContext {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PromptImproverGuideManagerTests-\(UUID().uuidString)", isDirectory: true)
        let appSupport = root.appendingPathComponent("AppSupport", isDirectory: true)
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        return GuideManagerTestContext(appSupportDirectory: appSupport, sourcesDirectory: sources)
    }
}

private struct GuideManagerTestContext {
    let appSupportDirectory: URL
    let sourcesDirectory: URL

    func makeManager(maxImportSizeBytes: Int) -> GuideDocumentManager {
        GuideDocumentManager(
            templates: Templates(bundle: .main, fallbackRoot: templateRootURL()),
            appSupportDirectory: appSupportDirectory,
            maxImportSizeBytes: maxImportSizeBytes
        )
    }
}
