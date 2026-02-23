import Foundation
import Testing
@testable import PromptImproverCore

@Suite(.serialized)
struct CLISmokeTests {
    private static var runSmoke: Bool {
        ProcessInfo.processInfo.environment["PROMPT_IMPROVER_RUN_CLI_SMOKE"] == "1"
    }

    private static var runRuntimeContractSmoke: Bool {
        ProcessInfo.processInfo.environment["PROMPT_IMPROVER_RUN_CLI_RUNTIME_CONTRACT"] == "1"
    }

    @Test(.enabled(if: Self.runSmoke))
    func codexSmokeRun() async throws {
        let discovery = CLIDiscovery()
        let codexURL = try #require(
            discovery.resolve(tool: .codex),
            "PROMPT_IMPROVER_RUN_CLI_SMOKE=1 requires codex in PATH."
        )

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

        for try await event in provider.run(request: request, workspace: workspace) {
            if case .completed(let prompt) = event {
                finalPrompt = prompt
            }
        }

        #expect(finalPrompt != nil)
        #expect(!(finalPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test(.enabled(if: Self.runSmoke))
    func claudeSmokeRun() async throws {
        let discovery = CLIDiscovery()
        let claudeURL = try #require(
            discovery.resolve(tool: .claude),
            "PROMPT_IMPROVER_RUN_CLI_SMOKE=1 requires claude in PATH."
        )

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

        for try await event in provider.run(request: request, workspace: workspace) {
            if case .completed(let prompt) = event {
                finalPrompt = prompt
            }
        }

        #expect(finalPrompt != nil)
        #expect(!(finalPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test(.enabled(if: Self.runRuntimeContractSmoke))
    func codexRuntimeContractWithRealCLIAndGuideContentVerification() async throws {
        let discovery = CLIDiscovery()
        let codexURL = try #require(
            discovery.resolve(tool: .codex),
            "PROMPT_IMPROVER_RUN_CLI_RUNTIME_CONTRACT=1 requires codex in PATH."
        )

        let captureRoot = try makeCaptureDirectory(name: "codex")
        defer { try? FileManager.default.removeItem(at: captureRoot) }

        let capturedPromptPath = captureRoot.appendingPathComponent("captured_prompt.txt")
        let capturedArgsPath = captureRoot.appendingPathComponent("captured_args.txt")
        let wrapperURL = try makeExecutableScript(
            name: "codex-runtime-wrapper",
            script: """
            #!/bin/zsh
            set -e
            args=("$@")
            out=""
            while [[ $# -gt 0 ]]; do
              if [[ "$1" == "--output-last-message" ]]; then
                out="$2"
                shift 2
                continue
              fi
              shift
            done

            cat > "\(capturedPromptPath.path)"
            printf "%s\\n" "${args[@]}" > "\(capturedArgsPath.path)"
            exec "\(codexURL.path)" "${args[@]}" < "\(capturedPromptPath.path)"
            """
        )
        defer { try? FileManager.default.removeItem(at: wrapperURL) }

        let templates = Templates(bundle: .main, fallbackRoot: templateRootURL())
        let manager = WorkspaceManager(templates: templates)
        let catalog = GuidesCatalog.default
        let gptGuide = try #require(catalog.guide(id: GuidesDefaults.gptGuideID))
        let geminiGuide = try #require(catalog.guide(id: GuidesDefaults.geminiGuideID))

        let request = makeRequest(
            tool: .codex,
            inputPrompt: "Convert this into a concise system prompt for coding tasks.",
            targetSlug: GuidesDefaults.gptOutputSlug,
            targetDisplayName: "GPT-5.2",
            mappedGuides: [gptGuide, geminiGuide]
        )
        let workspace = try manager.createRunWorkspace(request: request)
        defer { workspace.cleanup() }

        try assertWorkspaceGuidesMatchResolvedContent(
            mappedGuides: request.mappedGuides,
            guideFilenamesInOrder: workspace.guideFilenamesInOrder,
            workspaceRoot: workspace.path,
            templates: templates
        )

        #expect(FileManager.default.fileExists(atPath: workspace.path.appendingPathComponent("AGENTS.md").path))
        #expect(!FileManager.default.fileExists(atPath: workspace.path.appendingPathComponent("CLAUDE.md").path))

        let provider = CodexProvider(executableURL: wrapperURL)
        var finalPrompt: String?
        for try await event in provider.run(request: request, workspace: workspace) {
            if case .completed(let prompt) = event {
                finalPrompt = prompt
            }
        }
        #expect(finalPrompt != nil)
        #expect(!(finalPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let capturedPrompt = try String(contentsOf: capturedPromptPath, encoding: .utf8)
        #expect(capturedPrompt.contains("Read INPUT_PROMPT.txt in the current directory."))
        #expect(capturedPrompt.contains("Target output model: GPT-5.2 (slug: gpt-5-2)."))
        #expect(capturedPrompt.contains("Read and apply these guide files in exact order:"))
        #expect(capturedPrompt.contains("- guides/001-builtin-guide-gpt-5-2.md"))
        #expect(capturedPrompt.contains("- guides/002-builtin-guide-gemini-3-0.md"))
        #expect(!capturedPrompt.contains("TARGET_MODEL.txt"))
        #expect(!capturedPrompt.contains("RUN_CONFIG.json"))
    }

    @Test(.enabled(if: Self.runRuntimeContractSmoke))
    func claudeRuntimeContractWithRealCLIAndGuideContentVerification() async throws {
        let discovery = CLIDiscovery()
        let claudeURL = try #require(
            discovery.resolve(tool: .claude),
            "PROMPT_IMPROVER_RUN_CLI_RUNTIME_CONTRACT=1 requires claude in PATH."
        )

        let captureRoot = try makeCaptureDirectory(name: "claude")
        defer { try? FileManager.default.removeItem(at: captureRoot) }

        let capturedPromptPath = captureRoot.appendingPathComponent("captured_prompt.txt")
        let capturedArgsPath = captureRoot.appendingPathComponent("captured_args.txt")
        let wrapperURL = try makeExecutableScript(
            name: "claude-runtime-wrapper",
            script: """
            #!/bin/zsh
            set -e
            saved_prompt=""
            args=("$@")
            while [[ $# -gt 0 ]]; do
              if [[ "$1" == "-p" ]]; then
                saved_prompt="$2"
                break
              fi
              shift
            done

            printf "%s" "$saved_prompt" > "\(capturedPromptPath.path)"
            printf "%s\\n" "${args[@]}" > "\(capturedArgsPath.path)"
            exec "\(claudeURL.path)" "${args[@]}"
            """
        )
        defer { try? FileManager.default.removeItem(at: wrapperURL) }

        let templates = Templates(bundle: .main, fallbackRoot: templateRootURL())
        let manager = WorkspaceManager(templates: templates)
        let catalog = GuidesCatalog.default
        let claudeGuide = try #require(catalog.guide(id: GuidesDefaults.claudeGuideID))
        let gptGuide = try #require(catalog.guide(id: GuidesDefaults.gptGuideID))

        let request = makeRequest(
            tool: .claude,
            inputPrompt: "Rewrite this prompt for high-precision analysis tasks.",
            targetSlug: GuidesDefaults.claudeOutputSlug,
            targetDisplayName: "Claude 4.6",
            mappedGuides: [claudeGuide, gptGuide]
        )
        let workspace = try manager.createRunWorkspace(request: request)
        defer { workspace.cleanup() }

        try assertWorkspaceGuidesMatchResolvedContent(
            mappedGuides: request.mappedGuides,
            guideFilenamesInOrder: workspace.guideFilenamesInOrder,
            workspaceRoot: workspace.path,
            templates: templates
        )

        #expect(FileManager.default.fileExists(atPath: workspace.path.appendingPathComponent("CLAUDE.md").path))
        #expect(FileManager.default.fileExists(atPath: workspace.path.appendingPathComponent(".claude/settings.json").path))
        #expect(!FileManager.default.fileExists(atPath: workspace.path.appendingPathComponent("AGENTS.md").path))

        let provider = ClaudeProvider(executableURL: wrapperURL)
        var finalPrompt: String?
        for try await event in provider.run(request: request, workspace: workspace) {
            if case .completed(let prompt) = event {
                finalPrompt = prompt
            }
        }
        #expect(finalPrompt != nil)
        #expect(!(finalPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let capturedPrompt = try String(contentsOf: capturedPromptPath, encoding: .utf8)
        #expect(capturedPrompt.contains("Read INPUT_PROMPT.txt in the current directory."))
        #expect(capturedPrompt.contains("Target output model: Claude 4.6 (slug: claude-4-6)."))
        #expect(capturedPrompt.contains("Read and apply these guide files in exact order:"))
        #expect(capturedPrompt.contains("- guides/001-builtin-guide-claude-4-6.md"))
        #expect(capturedPrompt.contains("- guides/002-builtin-guide-gpt-5-2.md"))
        #expect(!capturedPrompt.contains("TARGET_MODEL.txt"))
        #expect(!capturedPrompt.contains("RUN_CONFIG.json"))
    }

    private func makeRequest(
        tool: Tool,
        inputPrompt: String,
        targetSlug: String? = nil,
        targetDisplayName: String? = nil,
        mappedGuides: [GuideDoc]? = nil
    ) -> RunRequest {
        let catalog = GuidesCatalog.default
        let resolvedTargetSlug = targetSlug ?? ((tool == .claude) ? GuidesDefaults.claudeOutputSlug : GuidesDefaults.gptOutputSlug)
        let outputModel = catalog.outputModel(slug: resolvedTargetSlug) ?? catalog.outputModels.first!

        return RunRequest(
            tool: tool,
            targetSlug: outputModel.slug,
            targetDisplayName: targetDisplayName ?? outputModel.displayName,
            mappedGuides: mappedGuides ?? catalog.orderedGuides(forOutputSlug: outputModel.slug),
            inputPrompt: inputPrompt
        )
    }

    private func makeCaptureDirectory(name: String) throws -> URL {
        try TestSupport.makeTemporaryDirectory(prefix: "RuntimeContract-\(name)")
    }

    private func makeExecutableScript(name: String, script: String) throws -> URL {
        try TestSupport.makeExecutableScript(
            name: "\(name)-\(UUID().uuidString).sh",
            script: script,
            prefix: "RuntimeContractScripts"
        )
    }

    private func assertWorkspaceGuidesMatchResolvedContent(
        mappedGuides: [GuideDoc],
        guideFilenamesInOrder: [String],
        workspaceRoot: URL,
        templates: Templates
    ) throws {
        #expect(guideFilenamesInOrder.count == mappedGuides.count)
        let guideManager = GuideDocumentManager(templates: templates)
        for (index, guide) in mappedGuides.enumerated() {
            let relativePath = guideFilenamesInOrder[index]
            let copiedGuideData = try Data(contentsOf: workspaceRoot.appendingPathComponent(relativePath))
            let resolvedGuideData = try guideManager.data(for: guide)
            #expect(copiedGuideData == resolvedGuideData)
        }
    }
}
