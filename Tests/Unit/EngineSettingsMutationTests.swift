import Foundation
import Testing
@testable import PromptImproverCore

struct EngineSettingsMutationTests {
    @Test
    func orderedOverrideTakesPrecedenceOverSeedAndCustom() {
        var settings = EngineSettings.default
        settings[.codex] = ToolEngineSettings(
            defaultEngineModel: "ordered-b",
            defaultEffort: .medium,
            customEngineModels: ["custom-a", "custom-b"],
            orderedEngineModels: ["ordered-a", "ordered-b"],
            perModelEffortAllowlist: [
                "ordered-b": [.low, .medium]
            ]
        )

        let resolved = settings.resolvedEngineModels(for: .codex)

        #expect(resolved == ["ordered-a", "ordered-b"])
        #expect(settings.resolvedDefaultEngineModel(for: .codex) == "ordered-b")
    }

    @Test
    func setOrderedModelsPrunesInvalidDefaultAndAllowlistEntries() {
        var settings = EngineSettings.default
        settings[.codex] = ToolEngineSettings(
            defaultEngineModel: "model-a",
            defaultEffort: .high,
            customEngineModels: [],
            orderedEngineModels: ["model-a", "model-b", "model-c"],
            perModelEffortAllowlist: [
                "model-a": [.low],
                "model-b": [.medium],
                "model-c": [.high]
            ]
        )

        settings.setOrderedEngineModels(["model-b", "model-c"], for: .codex)

        #expect(settings.resolvedEngineModels(for: .codex) == ["model-b", "model-c"])
        #expect(settings[.codex].defaultEngineModel == nil)
        #expect(settings[.codex].perModelEffortAllowlist["model-a"] == nil)
        #expect(settings[.codex].perModelEffortAllowlist["model-b"] == [.medium])
        #expect(settings[.codex].perModelEffortAllowlist["model-c"] == [.high])
    }

    @Test
    func resetToolToDefaultsOnlyResetsSelectedTool() {
        var settings = EngineSettings.default
        settings[.codex] = ToolEngineSettings(
            defaultEngineModel: "model-codex",
            defaultEffort: .low,
            customEngineModels: [],
            orderedEngineModels: ["model-codex"],
            perModelEffortAllowlist: [
                "model-codex": [.low]
            ]
        )
        settings[.claude] = ToolEngineSettings(
            defaultEngineModel: "model-claude",
            defaultEffort: .high,
            customEngineModels: [],
            orderedEngineModels: ["model-claude"],
            perModelEffortAllowlist: [
                "model-claude": [.high]
            ]
        )

        settings.resetToolToDefaults(.codex)

        #expect(settings[.codex].orderedEngineModels == nil)
        #expect(settings[.codex].defaultEngineModel == nil)
        #expect(settings[.codex].perModelEffortAllowlist.isEmpty)

        #expect(settings[.claude].orderedEngineModels == ["model-claude"])
        #expect(settings[.claude].defaultEngineModel == "model-claude")
        #expect(settings[.claude].perModelEffortAllowlist["model-claude"] == [.high])
    }
}
