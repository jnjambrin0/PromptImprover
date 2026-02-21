import Foundation
import Testing
@testable import PromptImproverCore

struct WorkspaceManagerTests {
    @Test
    func workspaceContainsRuntimeFilesAndTemplates() throws {
        let templates = Templates(bundle: .main, fallbackRoot: templateRootURL())
        let manager = WorkspaceManager(templates: templates)

        let request = RunRequest(tool: .codex, targetModel: .gpt52, inputPrompt: "Hello")
        let workspace = try manager.createRunWorkspace(request: request)
        defer { workspace.cleanup() }

        #expect(FileManager.default.fileExists(atPath: workspace.inputPromptPath.path))
        #expect(FileManager.default.fileExists(atPath: workspace.targetModelPath.path))
        #expect(FileManager.default.fileExists(atPath: workspace.runConfigPath.path))
        #expect(FileManager.default.fileExists(atPath: workspace.schemaPath.path))

        let agentsPath = workspace.path.appendingPathComponent("AGENTS.md").path
        #expect(FileManager.default.fileExists(atPath: agentsPath))
    }

    @Test
    func workspaceIsUnderTemporaryDirectory() throws {
        let templates = Templates(bundle: .main, fallbackRoot: templateRootURL())
        let manager = WorkspaceManager(templates: templates)

        let request = RunRequest(tool: .codex, targetModel: .gpt52, inputPrompt: "Hello")
        let workspace = try manager.createRunWorkspace(request: request)
        defer { workspace.cleanup() }

        #expect(workspace.path.path.hasPrefix(NSTemporaryDirectory()))
    }

    @Test
    func claudeWorkspaceWritesEffortLevelWhenConfigured() throws {
        let templates = Templates(bundle: .main, fallbackRoot: templateRootURL())
        let manager = WorkspaceManager(templates: templates)

        let request = RunRequest(
            tool: .claude,
            targetModel: .claude46,
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

        let codexRequest = RunRequest(
            tool: .codex,
            targetModel: .gpt52,
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

        let claudeRequestWithoutEffort = RunRequest(
            tool: .claude,
            targetModel: .claude46,
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
}
