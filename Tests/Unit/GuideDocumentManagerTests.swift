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
        #expect(imported.storagePath.hasPrefix("guides/user/"))
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
    func resolvesBuiltInGuidesFromMaterializedAppSupportCopy() throws {
        let context = try makeContext()
        let manager = context.makeManager(maxImportSizeBytes: 1_048_576)
        let guide = try #require(GuidesCatalog.default.guide(id: GuidesDefaults.gptGuideID))

        let data = try manager.data(for: guide)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("GPT-5.2"))
        let copiedURL = context.appSupportDirectory.appendingPathComponent(guide.storagePath)
        #expect(FileManager.default.fileExists(atPath: copiedURL.path))
    }

    @Test
    func ensureEditableGuideCreatesForkForBuiltInGuide() throws {
        let context = try makeContext()
        let manager = context.makeManager(maxImportSizeBytes: 1_048_576)
        let builtInGuide = try #require(GuidesCatalog.default.guide(id: GuidesDefaults.gptGuideID))

        let editable = try manager.ensureEditableGuide(builtInGuide)
        let forkPath = try #require(editable.forkStoragePath)
        #expect(editable.isBuiltIn)
        #expect(forkPath.hasPrefix("guides/user/forks/"))
        #expect(manager.hasFork(for: editable))

        let forkURL = context.appSupportDirectory.appendingPathComponent(forkPath)
        #expect(FileManager.default.fileExists(atPath: forkURL.path))
    }

    @Test
    func builtInGuidePrefersForkAndRevertReturnsToTemplateContent() throws {
        let context = try makeContext()
        let manager = context.makeManager(maxImportSizeBytes: 1_048_576)
        let builtInGuide = try #require(GuidesCatalog.default.guide(id: GuidesDefaults.gptGuideID))
        let templateText = try manager.loadText(for: builtInGuide)

        let editable = try manager.ensureEditableGuide(builtInGuide)
        let customBody = "# Custom Forked Guide\n\nOnly this should be used.\n"
        let saved = try manager.saveText(customBody, for: editable)

        let savedText = try manager.loadText(for: saved)
        #expect(savedText == customBody)
        #expect(saved.hash != nil)
        #expect(saved.updatedAt.timeIntervalSince1970 > builtInGuide.updatedAt.timeIntervalSince1970)

        let reverted = try manager.revertBuiltInFork(for: saved)
        #expect(reverted.forkStoragePath == nil)
        #expect(reverted.hash == nil)
        #expect(!manager.hasFork(for: reverted))

        let revertedText = try manager.loadText(for: reverted)
        #expect(revertedText == templateText)
    }

    @Test
    func saveTextIsAtomicAndCleansTemporaryFiles() throws {
        let context = try makeContext()
        let manager = context.makeManager(maxImportSizeBytes: 1_048_576)
        let builtInGuide = try #require(GuidesCatalog.default.guide(id: GuidesDefaults.gptGuideID))
        let editable = try manager.ensureEditableGuide(builtInGuide)

        let saved = try manager.saveText("# Atomic Save\n\nCheck temp files.\n", for: editable)
        let forkStoragePath = try #require(saved.forkStoragePath)
        let forkFileName = URL(fileURLWithPath: forkStoragePath).lastPathComponent
        let tempPrefix = ".\(forkFileName).tmp-"

        let forkDirectory = context.appSupportDirectory.appendingPathComponent("guides/user/forks", isDirectory: true)
        let directoryEntries = try FileManager.default.contentsOfDirectory(atPath: forkDirectory.path)
        #expect(directoryEntries.contains(where: { $0.hasPrefix(tempPrefix) }) == false)
    }

    @Test
    func saveTextUpdatesUserGuideInPlace() throws {
        let context = try makeContext()
        let manager = context.makeManager(maxImportSizeBytes: 1_048_576)

        let sourceURL = context.sourcesDirectory.appendingPathComponent("user-guide.md")
        try Data("# Original\n".utf8).write(to: sourceURL, options: .atomic)
        let imported = try manager.importGuide(from: sourceURL)

        let updatedBody = "# Updated\n\nPersisted text.\n"
        let saved = try manager.saveText(updatedBody, for: imported)

        #expect(saved.isBuiltIn == false)
        #expect(saved.hash != nil)
        #expect(try manager.loadText(for: saved) == updatedBody)
    }

    private func makeContext() throws -> GuideManagerTestContext {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PromptImproverGuideManagerTests-\(UUID().uuidString)", isDirectory: true)
        let appSupport = root.appendingPathComponent("AppSupport", isDirectory: true)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("Temporary", isDirectory: true)
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        return GuideManagerTestContext(
            storageLayout: AppStorageLayout(
                appSupportRoot: appSupport,
                cachesRoot: caches,
                temporaryRoot: temporary
            ),
            sourcesDirectory: sources
        )
    }
}

private struct GuideManagerTestContext {
    let storageLayout: AppStorageLayout
    let sourcesDirectory: URL

    var appSupportDirectory: URL { storageLayout.appSupportRoot }

    func makeManager(maxImportSizeBytes: Int) -> GuideDocumentManager {
        GuideDocumentManager(
            templates: Templates(bundle: .main, fallbackRoot: templateRootURL()),
            storageLayout: storageLayout,
            maxImportSizeBytes: maxImportSizeBytes
        )
    }
}
