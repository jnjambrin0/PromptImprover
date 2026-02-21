import Foundation
import Testing
@testable import PromptImproverCore

struct EngineSettingsStoreTests {
    @Test
    func roundTripsFullPayload() throws {
        let fileURL = makeSettingsFileURL()
        let store = EngineSettingsStore(fileURL: fileURL)

        var settings = EngineSettings.default
        settings[.codex] = ToolEngineSettings(
            defaultEngineModel: "gpt-5-mini",
            defaultEffort: .medium,
            customEngineModels: ["gpt-5-experimental", "o3-pro"],
            perModelEffortAllowlist: [
                "gpt-5-mini": [.low, .medium],
                "o3-pro": [.high]
            ]
        )
        settings[.claude] = ToolEngineSettings(
            defaultEngineModel: "claude-opus-4-6",
            defaultEffort: .high,
            customEngineModels: ["claude-opus-4-5-preview"],
            perModelEffortAllowlist: [
                "claude-opus-4-6": [.low, .medium, .high]
            ]
        )

        try store.save(settings)
        let loaded = store.load()

        #expect(loaded == settings)
        #expect(loaded[.codex].defaultEngineModel == "gpt-5-mini")
        #expect(loaded[.claude].defaultEffort == .high)
    }

    @Test
    func roundTripsOrderedEngineModelsOverride() throws {
        let fileURL = makeSettingsFileURL()
        let store = EngineSettingsStore(fileURL: fileURL)

        var settings = EngineSettings.default
        settings[.codex] = ToolEngineSettings(
            defaultEngineModel: "ordered-b",
            defaultEffort: .medium,
            customEngineModels: ["legacy-custom"],
            orderedEngineModels: ["ordered-a", "ordered-b"],
            perModelEffortAllowlist: [
                "ordered-b": [.medium]
            ]
        )

        try store.save(settings)
        let loaded = store.load()

        #expect(loaded[.codex].orderedEngineModels == ["ordered-a", "ordered-b"])
        #expect(loaded.resolvedEngineModels(for: .codex) == ["ordered-a", "ordered-b"])
        #expect(loaded[.codex].customEngineModels == ["legacy-custom"])
    }

    @Test
    func decodesPayloadWithoutSchemaVersion() throws {
        let fileURL = makeSettingsFileURL()
        let json = """
        {
          "settingsByTool": {
            "codex": {
              "defaultEngineModel": "gpt-5",
              "defaultEffort": "low",
              "customEngineModels": ["custom-a", "custom-b"],
              "perModelEffortAllowlist": {
                "gpt-5": ["low", "medium"]
              }
            }
          }
        }
        """
        try Data(json.utf8).write(to: fileURL, options: .atomic)

        let store = EngineSettingsStore(fileURL: fileURL)
        let loaded = store.load()

        #expect(loaded[.codex].defaultEngineModel == "gpt-5")
        #expect(loaded[.codex].defaultEffort == .low)
        #expect(loaded[.codex].customEngineModels == ["custom-a", "custom-b"])
    }

    @Test
    func ignoresUnknownFieldsDuringDecode() throws {
        let fileURL = makeSettingsFileURL()
        let json = """
        {
          "schemaVersion": 1,
          "unknown_top_level": "ignored",
          "settingsByTool": {
            "claude": {
              "defaultEngineModel": "claude-sonnet-4-6",
              "defaultEffort": "medium",
              "customEngineModels": ["claude-custom"],
              "perModelEffortAllowlist": {
                "claude-opus-4-6": ["high"]
              },
              "future_field": {
                "anything": true
              }
            }
          }
        }
        """
        try Data(json.utf8).write(to: fileURL, options: .atomic)

        let store = EngineSettingsStore(fileURL: fileURL)
        let loaded = store.load()

        #expect(loaded[.claude].defaultEngineModel == "claude-sonnet-4-6")
        #expect(loaded[.claude].defaultEffort == .medium)
        #expect(loaded[.claude].customEngineModels == ["claude-custom"])
        #expect(loaded[.claude].perModelEffortAllowlist["claude-opus-4-6"] == [.high])
    }

    @Test
    func ignoresUnknownToolEntries() throws {
        let fileURL = makeSettingsFileURL()
        let json = """
        {
          "schemaVersion": 1,
          "settingsByTool": {
            "codex": {
              "defaultEngineModel": "gpt-5",
              "defaultEffort": "medium",
              "customEngineModels": ["custom-codex"],
              "perModelEffortAllowlist": {
                "gpt-5": ["medium"]
              }
            },
            "future_tool": {
              "defaultEngineModel": "future-model",
              "defaultEffort": "high",
              "customEngineModels": ["x"],
              "perModelEffortAllowlist": {
                "future-model": ["high"]
              }
            }
          }
        }
        """
        try Data(json.utf8).write(to: fileURL, options: .atomic)

        let store = EngineSettingsStore(fileURL: fileURL)
        let loaded = store.load()

        #expect(loaded[.codex].defaultEngineModel == "gpt-5")
        #expect(loaded.byTool.count == 1)
    }

    @Test
    func preservesCustomModelOrder() throws {
        let fileURL = makeSettingsFileURL()
        let store = EngineSettingsStore(fileURL: fileURL)

        var settings = EngineSettings.default
        settings[.codex] = ToolEngineSettings(
            defaultEngineModel: "model-b",
            defaultEffort: nil,
            customEngineModels: ["model-b", "model-a", "model-c"],
            perModelEffortAllowlist: [:]
        )

        try store.save(settings)
        let loaded = store.load()

        #expect(loaded[.codex].customEngineModels == ["model-b", "model-a", "model-c"])
    }

    private func makeSettingsFileURL() -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PromptImproverTests", isDirectory: true)
            .appendingPathComponent("EngineSettingsStore-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("engine_settings.json")
    }
}
