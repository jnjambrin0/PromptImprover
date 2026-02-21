import Foundation
import Testing
@testable import PromptImproverCore

struct GuidesCatalogStoreTests {
    @Test
    func roundTripsCatalogPayload() throws {
        let fileURL = makeCatalogFileURL()
        let store = GuidesCatalogStore(fileURL: fileURL)

        let guide = GuideDoc(
            id: "guide-user-1",
            title: "User One",
            storagePath: "guides/guide-user-1.md",
            isBuiltIn: false,
            updatedAt: Date(timeIntervalSince1970: 2_000),
            hash: "abc123"
        )

        var catalog = GuidesCatalog.default
        catalog.upsertGuide(guide)
        _ = try catalog.addOutputModel(displayName: "Custom", slug: "custom-model")
        try catalog.appendGuide(guide.id, toOutputModel: "custom-model")

        try store.save(catalog)
        let loaded = store.load()

        #expect(loaded == catalog.reconciled())
    }

    @Test
    func ignoresUnknownFieldsOnDecode() throws {
        let fileURL = makeCatalogFileURL()
        let json = """
        {
          "schemaVersion": 1,
          "futureTopLevel": true,
          "outputModels": [
            {
              "displayName": "Custom",
              "slug": "custom-model",
              "guideIds": ["guide-user-1"],
              "futureField": 123
            }
          ],
          "guides": [
            {
              "id": "guide-user-1",
              "title": "User Guide",
              "storagePath": "guides/guide-user-1.md",
              "isBuiltIn": false,
              "updatedAt": 700000000,
              "hash": "deadbeef",
              "anotherFutureField": "ignored"
            }
          ]
        }
        """
        try Data(json.utf8).write(to: fileURL, options: .atomic)

        let store = GuidesCatalogStore(fileURL: fileURL)
        let loaded = store.load()

        #expect(loaded.outputModel(slug: "custom-model") != nil)
        #expect(loaded.guide(id: "guide-user-1") != nil)
    }

    @Test
    func fallsBackToDefaultsWhenFileMissingOrCorrupt() throws {
        let missingFileURL = makeCatalogFileURL()
        let missingStore = GuidesCatalogStore(fileURL: missingFileURL)
        #expect(missingStore.load() == GuidesCatalog.default)

        let corruptFileURL = makeCatalogFileURL()
        try Data("not-json".utf8).write(to: corruptFileURL, options: .atomic)
        let corruptStore = GuidesCatalogStore(fileURL: corruptFileURL)
        #expect(corruptStore.load() == GuidesCatalog.default)
    }

    @Test
    func preservesOrderingAcrossSaveAndLoad() throws {
        let fileURL = makeCatalogFileURL()
        let store = GuidesCatalogStore(fileURL: fileURL)

        let guideA = GuideDoc(
            id: "guide-a",
            title: "A",
            storagePath: "guides/a.md",
            isBuiltIn: false,
            updatedAt: Date(timeIntervalSince1970: 3_000)
        )
        let guideB = GuideDoc(
            id: "guide-b",
            title: "B",
            storagePath: "guides/b.md",
            isBuiltIn: false,
            updatedAt: Date(timeIntervalSince1970: 3_001)
        )

        var catalog = GuidesCatalog(outputModels: [], guides: [])
        catalog.upsertGuide(guideA)
        catalog.upsertGuide(guideB)
        _ = try catalog.addOutputModel(displayName: "Model B", slug: "model-b")
        _ = try catalog.addOutputModel(displayName: "Model A", slug: "model-a")
        try catalog.appendGuide(guideB.id, toOutputModel: "model-a")
        try catalog.appendGuide(guideA.id, toOutputModel: "model-a")

        try store.save(catalog)
        let loaded = store.load()

        #expect(loaded.outputModels.map(\.slug) == ["model-b", "model-a"])
        #expect(loaded.outputModel(slug: "model-a")?.guideIds == ["guide-b", "guide-a"])
        #expect(loaded.guides.map(\.id) == ["guide-a", "guide-b"])
    }

    private func makeCatalogFileURL() -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PromptImproverTests", isDirectory: true)
            .appendingPathComponent("GuidesCatalogStore-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("guides_catalog.json")
    }
}
