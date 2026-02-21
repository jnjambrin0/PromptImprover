import Foundation
import Testing
@testable import PromptImproverCore

struct WorkspaceManagerTests {
    @Test
    func workspaceContainsRuntimeFilesAndStaticTemplates() throws {
        let templates = Templates(bundle: .main, fallbackRoot: templateRootURL())
        let manager = WorkspaceManager(templates: templates)

        let request = makeRequest(tool: .codex, mappedGuides: [])
        let workspace = try manager.createRunWorkspace(request: request)
        defer { workspace.cleanup() }

        #expect(FileManager.default.fileExists(atPath: workspace.inputPromptPath.path))
        #expect(FileManager.default.fileExists(atPath: workspace.targetModelPath.path))
        #expect(FileManager.default.fileExists(atPath: workspace.runConfigPath.path))
        #expect(FileManager.default.fileExists(atPath: workspace.schemaPath.path))

        #expect(FileManager.default.fileExists(atPath: workspace.path.appendingPathComponent("AGENTS.md").path))
        #expect(FileManager.default.fileExists(atPath: workspace.path.appendingPathComponent("CLAUDE.md").path))
        #expect(FileManager.default.fileExists(atPath: workspace.path.appendingPathComponent(".claude/settings.json").path))
    }

    @Test
    func workspaceCopiesOnlyMappedGuidesInOrderAndWritesRunConfig() throws {
        let templates = Templates(bundle: .main, fallbackRoot: templateRootURL())
        let manager = WorkspaceManager(templates: templates)

        let catalog = GuidesCatalog.default
        let gptGuide = try #require(catalog.guide(id: GuidesDefaults.gptGuideID))
        let claudeGuide = try #require(catalog.guide(id: GuidesDefaults.claudeGuideID))

        let request = makeRequest(
            tool: .codex,
            targetSlug: "custom-target",
            targetDisplayName: "Custom Target",
            mappedGuides: [gptGuide, claudeGuide]
        )

        let workspace = try manager.createRunWorkspace(request: request)
        defer { workspace.cleanup() }

        let expected = [
            "guides/001-builtin-guide-gpt-5-2.md",
            "guides/002-builtin-guide-claude-4-6.md"
        ]
        for relative in expected {
            #expect(FileManager.default.fileExists(atPath: workspace.path.appendingPathComponent(relative).path))
        }

        let runConfigData = try Data(contentsOf: workspace.runConfigPath)
        let runConfig = try JSONDecoder().decode(WorkspaceRunConfigFixture.self, from: runConfigData)
        #expect(runConfig.targetSlug == "custom-target")
        #expect(runConfig.guideFilenamesInOrder == expected)

        let guideDirectory = workspace.path.appendingPathComponent("guides")
        let guideFileNames = try FileManager.default.contentsOfDirectory(atPath: guideDirectory.path)
        #expect(guideFileNames.count == 2)
    }

    @Test
    func workspaceDoesNotCopyUnmappedGuides() throws {
        let templates = Templates(bundle: .main, fallbackRoot: templateRootURL())
        let manager = WorkspaceManager(templates: templates)

        let catalog = GuidesCatalog.default
        let gptGuide = try #require(catalog.guide(id: GuidesDefaults.gptGuideID))

        let request = makeRequest(
            tool: .codex,
            targetSlug: GuidesDefaults.gptOutputSlug,
            targetDisplayName: "GPT-5.2",
            mappedGuides: [gptGuide]
        )

        let workspace = try manager.createRunWorkspace(request: request)
        defer { workspace.cleanup() }

        #expect(FileManager.default.fileExists(atPath: workspace.path.appendingPathComponent("guides/001-builtin-guide-gpt-5-2.md").path))
        #expect(!FileManager.default.fileExists(atPath: workspace.path.appendingPathComponent("guides/002-builtin-guide-claude-4-6.md").path))
        #expect(!FileManager.default.fileExists(atPath: workspace.path.appendingPathComponent("guides/003-builtin-guide-gemini-3-0.md").path))
    }

    @Test
    func workspaceIsUnderTemporaryDirectory() throws {
        let templates = Templates(bundle: .main, fallbackRoot: templateRootURL())
        let manager = WorkspaceManager(templates: templates)

        let request = makeRequest(tool: .codex, mappedGuides: [])
        let workspace = try manager.createRunWorkspace(request: request)
        defer { workspace.cleanup() }

        #expect(workspace.path.path.hasPrefix(NSTemporaryDirectory()))
    }

    @Test
    func claudeWorkspaceWritesEffortLevelWhenConfigured() throws {
        let templates = Templates(bundle: .main, fallbackRoot: templateRootURL())
        let manager = WorkspaceManager(templates: templates)

        let request = makeRequest(
            tool: .claude,
            targetSlug: GuidesDefaults.claudeOutputSlug,
            targetDisplayName: "Claude 4.6",
            mappedGuides: GuidesCatalog.default.orderedGuides(forOutputSlug: GuidesDefaults.claudeOutputSlug),
            inputPrompt: "Hello",
            engineModel: "claude-opus-4-6",
            engineEffort: .medium
        )
        let workspace = try manager.createRunWorkspace(request: request)
        defer { workspace.cleanup() }

        let settingsPath = workspace.path.appendingPathComponent(".claude/settings.json")
        let data = try Data(contentsOf: settingsPath)
        let object = try JSONSerialization.jsonObject(with: data)
        let settings = try #require(object as? [String: Any])

        #expect(settings["effortLevel"] as? String == "medium")
        #expect(settings["memory"] != nil)
    }

    @Test
    func workspaceDoesNotWriteEffortLevelForNonClaudeOrMissingEffort() throws {
        let templates = Templates(bundle: .main, fallbackRoot: templateRootURL())
        let manager = WorkspaceManager(templates: templates)

        let codexRequest = makeRequest(
            tool: .codex,
            targetSlug: GuidesDefaults.gptOutputSlug,
            targetDisplayName: "GPT-5.2",
            mappedGuides: GuidesCatalog.default.orderedGuides(forOutputSlug: GuidesDefaults.gptOutputSlug),
            inputPrompt: "Hello",
            engineModel: "gpt-5",
            engineEffort: .high
        )
        let codexWorkspace = try manager.createRunWorkspace(request: codexRequest)
        defer { codexWorkspace.cleanup() }

        let codexSettingsPath = codexWorkspace.path.appendingPathComponent(".claude/settings.json")
        let codexData = try Data(contentsOf: codexSettingsPath)
        let codexObject = try JSONSerialization.jsonObject(with: codexData)
        let codexSettings = try #require(codexObject as? [String: Any])
        #expect(codexSettings["effortLevel"] == nil)

        let claudeRequestWithoutEffort = makeRequest(
            tool: .claude,
            targetSlug: GuidesDefaults.claudeOutputSlug,
            targetDisplayName: "Claude 4.6",
            mappedGuides: GuidesCatalog.default.orderedGuides(forOutputSlug: GuidesDefaults.claudeOutputSlug),
            inputPrompt: "Hello",
            engineModel: "claude-opus-4-6",
            engineEffort: nil
        )
        let claudeWorkspace = try manager.createRunWorkspace(request: claudeRequestWithoutEffort)
        defer { claudeWorkspace.cleanup() }

        let claudeSettingsPath = claudeWorkspace.path.appendingPathComponent(".claude/settings.json")
        let claudeData = try Data(contentsOf: claudeSettingsPath)
        let claudeObject = try JSONSerialization.jsonObject(with: claudeData)
        let claudeSettings = try #require(claudeObject as? [String: Any])
        #expect(claudeSettings["effortLevel"] == nil)
    }

    private func makeRequest(
        tool: Tool,
        targetSlug: String = GuidesDefaults.gptOutputSlug,
        targetDisplayName: String = "GPT-5.2",
        mappedGuides: [GuideDoc],
        inputPrompt: String = "Hello",
        engineModel: String? = nil,
        engineEffort: EngineEffort? = nil
    ) -> RunRequest {
        RunRequest(
            tool: tool,
            targetSlug: targetSlug,
            targetDisplayName: targetDisplayName,
            mappedGuides: mappedGuides,
            inputPrompt: inputPrompt,
            engineModel: engineModel,
            engineEffort: engineEffort
        )
    }
}

private struct WorkspaceRunConfigFixture: Codable {
    let targetSlug: String
    let guideFilenamesInOrder: [String]
}
