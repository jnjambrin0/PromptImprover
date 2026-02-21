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
}
