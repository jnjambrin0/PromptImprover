import Foundation
import Testing
@testable import PromptImproverCore

struct GuidesCatalogMutationTests {
    @Test
    func preservesOrderedGuideAssignmentsAndReorderSemantics() throws {
        var catalog = GuidesCatalog.default
        _ = try catalog.addOutputModel(displayName: "Custom Model", slug: "custom-model")

        try catalog.appendGuide(GuidesDefaults.gptGuideID, toOutputModel: "custom-model")
        try catalog.appendGuide(GuidesDefaults.claudeGuideID, toOutputModel: "custom-model")
        try catalog.appendGuide(GuidesDefaults.geminiGuideID, toOutputModel: "custom-model")

        #expect(catalog.outputModel(slug: "custom-model")?.guideIds == [
            GuidesDefaults.gptGuideID,
            GuidesDefaults.claudeGuideID,
            GuidesDefaults.geminiGuideID
        ])

        try catalog.moveGuide(forOutputModel: "custom-model", from: 2, to: 0)
        #expect(catalog.outputModel(slug: "custom-model")?.guideIds == [
            GuidesDefaults.geminiGuideID,
            GuidesDefaults.gptGuideID,
            GuidesDefaults.claudeGuideID
        ])

        try catalog.removeGuide(GuidesDefaults.gptGuideID, fromOutputModel: "custom-model")
        #expect(catalog.outputModel(slug: "custom-model")?.guideIds == [
            GuidesDefaults.geminiGuideID,
            GuidesDefaults.claudeGuideID
        ])
    }

    @Test
    func normalizesSlugAndRejectsDuplicateSlugsCaseInsensitively() throws {
        var catalog = GuidesCatalog.default
        let added = try catalog.addOutputModel(displayName: "Custom", slug: "  GPT 5.2 ++ Custom  ")
        #expect(added.slug == "gpt-5-2-custom")

        do {
            _ = try catalog.addOutputModel(displayName: "Duplicate", slug: "gPt-5-2-CUSTOM")
            Issue.record("Expected duplicate slug failure")
        } catch {
            #expect(error as? GuidesCatalogError == .duplicateSlug)
        }
    }

    @Test
    func deletingUserGuideUnassignsAllReferences() throws {
        var catalog = GuidesCatalog.default
        let userGuide = GuideDoc(
            id: "guide-user-123",
            title: "User Guide",
            storagePath: "guides/guide-user-123.md",
            isBuiltIn: false,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        catalog.upsertGuide(userGuide)

        try catalog.appendGuide(userGuide.id, toOutputModel: GuidesDefaults.gptOutputSlug)
        try catalog.appendGuide(userGuide.id, toOutputModel: GuidesDefaults.claudeOutputSlug)

        _ = try catalog.deleteGuide(id: userGuide.id)

        #expect(catalog.guide(id: userGuide.id) == nil)
        let gptGuideIDs = catalog.outputModel(slug: GuidesDefaults.gptOutputSlug)?.guideIds ?? []
        let claudeGuideIDs = catalog.outputModel(slug: GuidesDefaults.claudeOutputSlug)?.guideIds ?? []
        #expect(gptGuideIDs.contains(userGuide.id) == false)
        #expect(claudeGuideIDs.contains(userGuide.id) == false)
    }

    @Test
    func resetBuiltInsRestoresCanonicalBuiltInsAndPreservesUserEntries() throws {
        var catalog = GuidesCatalog.default
        let userGuide = GuideDoc(
            id: "guide-user-reset",
            title: "User Reset Guide",
            storagePath: "guides/guide-user-reset.md",
            isBuiltIn: false,
            updatedAt: Date(timeIntervalSince1970: 1_001)
        )

        catalog.upsertGuide(userGuide)
        _ = try catalog.addOutputModel(displayName: "User Model", slug: "user-model")
        try catalog.appendGuide(userGuide.id, toOutputModel: "user-model")

        try catalog.removeGuide(GuidesDefaults.claudeGuideID, fromOutputModel: GuidesDefaults.claudeOutputSlug)
        _ = try catalog.updateOutputModel(existingSlug: GuidesDefaults.claudeOutputSlug, displayName: "Mutated Claude", slug: GuidesDefaults.claudeOutputSlug)

        catalog.resetBuiltInsPreservingUserEntries()

        #expect(catalog.outputModels.prefix(3).map(\.slug) == GuidesDefaults.builtInOutputModels.map(\.slug))
        #expect(catalog.outputModel(slug: GuidesDefaults.claudeOutputSlug)?.displayName == "Claude 4.6")
        #expect(catalog.outputModel(slug: GuidesDefaults.claudeOutputSlug)?.guideIds == [GuidesDefaults.claudeGuideID])

        #expect(catalog.outputModel(slug: "user-model") != nil)
        #expect(catalog.guide(id: userGuide.id) != nil)
    }
}
