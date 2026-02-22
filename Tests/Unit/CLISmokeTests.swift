import Foundation
import Testing
@testable import PromptImproverCore

struct CLISmokeTests {
    private var runSmoke: Bool {
        ProcessInfo.processInfo.environment["PROMPT_IMPROVER_RUN_CLI_SMOKE"] == "1"
    }

    @Test
    func codexSmokeRun() async throws {
        guard runSmoke else {
            return
        }

        let discovery = CLIDiscovery()
        guard let codexURL = discovery.resolve(tool: .codex) else {
            print("Skipping Codex smoke: `codex` binary not found in PATH.")
            return
        }

        let templates = Templates(bundle: .main, fallbackRoot: templateRootURL())
        let manager = WorkspaceManager(templates: templates)
        let request = makeRequest(
            tool: .codex,
            inputPrompt: "Summarize this in one sentence: Swift is a language."
        )
        let workspace = try manager.createRunWorkspace(request: request)
        defer { workspace.cleanup() }

        let provider = CodexProvider(executableURL: codexURL)
        var finalPrompt: String?

        do {
            for try await event in provider.run(request: request, workspace: workspace) {
                if case .completed(let prompt) = event {
                    finalPrompt = prompt
                }
            }
        } catch let error as PromptImproverError {
            if case .toolNotAuthenticated(let details) = error {
                print("Skipping Codex smoke: not authenticated. \(details)")
                return
            }
            throw error
        }

        #expect(finalPrompt != nil)
        #expect(!(finalPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func claudeSmokeRun() async throws {
        guard runSmoke else {
            return
        }

        let discovery = CLIDiscovery()
        guard let claudeURL = discovery.resolve(tool: .claude) else {
            print("Skipping Claude smoke: `claude` binary not found in PATH.")
            return
        }

        let templates = Templates(bundle: .main, fallbackRoot: templateRootURL())
        let manager = WorkspaceManager(templates: templates)
        let request = makeRequest(
            tool: .claude,
            inputPrompt: "Explain recursion simply."
        )
        let workspace = try manager.createRunWorkspace(request: request)
        defer { workspace.cleanup() }

        let provider = ClaudeProvider(executableURL: claudeURL)
        var finalPrompt: String?

        do {
            for try await event in provider.run(request: request, workspace: workspace) {
                if case .completed(let prompt) = event {
                    finalPrompt = prompt
                }
            }
        } catch let error as PromptImproverError {
            if case .toolNotAuthenticated(let details) = error {
                print("Skipping Claude smoke: not authenticated. \(details)")
                return
            }
            throw error
        }

        #expect(finalPrompt != nil)
        #expect(!(finalPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func makeRequest(tool: Tool, inputPrompt: String) -> RunRequest {
        let catalog = GuidesCatalog.default
        let targetSlug = (tool == .claude) ? GuidesDefaults.claudeOutputSlug : GuidesDefaults.gptOutputSlug
        let outputModel = catalog.outputModel(slug: targetSlug) ?? catalog.outputModels.first!

        return RunRequest(
            tool: tool,
            targetSlug: outputModel.slug,
            targetDisplayName: outputModel.displayName,
            mappedGuides: catalog.orderedGuides(forOutputSlug: outputModel.slug),
            inputPrompt: inputPrompt
        )
    }
}
