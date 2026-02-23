import Foundation
import Testing
@testable import PromptImprover

@MainActor
@Suite(.serialized)
struct PromptImproverViewModelTests {
    @Test
    func improveDisabledReasonRequiresAtLeastOneOutputModel() throws {
        let guidesStoreURL = try AppTestSupport.makeTemporaryDirectory(prefix: "ViewModelGuidesStore")
            .appendingPathComponent("model-mapping.json")
        let guidesStore = GuidesCatalogStore(fileURL: guidesStoreURL)
        try guidesStore.save(GuidesCatalog(outputModels: [], guides: []))

        let provider = FakeCLIProvider(mode: .complete("unused"))
        let viewModel = try makeViewModel(guidesCatalogStore: guidesStore, provider: provider)
        viewModel.inputPrompt = "Improve this prompt."

        #expect(viewModel.improveDisabledReason == "Add at least one target output model in Settings → Guides.")
        #expect(viewModel.canImprove == false)
    }

    @Test
    func improveCompletesAndReconcilesInvalidTargetSelection() async throws {
        let provider = FakeCLIProvider(mode: .complete("optimized prompt"))
        let viewModel = try makeViewModel(provider: provider)
        viewModel.inputPrompt = "Improve this prompt."
        viewModel.selectedTargetSlug = "invalid-target-slug"

        #expect(await AppAsyncTestSupport.waitUntil(condition: { viewModel.canImprove }))
        viewModel.improve()

        #expect(await AppAsyncTestSupport.waitUntil(condition: { viewModel.status == .done }))
        #expect(viewModel.outputPrompt == "optimized prompt")
        #expect(viewModel.statusMessage == "Done")
        #expect(viewModel.selectedTargetSlug == viewModel.outputModels.first?.slug)
    }

    @Test
    func providerFailureMovesViewModelToErrorState() async throws {
        let provider = FakeCLIProvider(mode: .failed(.toolExecutionFailed("provider failed")))
        let viewModel = try makeViewModel(provider: provider)
        viewModel.inputPrompt = "Improve this prompt."

        #expect(await AppAsyncTestSupport.waitUntil(condition: { viewModel.canImprove }))
        viewModel.improve()

        #expect(await AppAsyncTestSupport.waitUntil(condition: { viewModel.status == .error }))
        #expect(viewModel.statusMessage == "Error")
        #expect(viewModel.errorMessage?.contains("provider failed") == true)
    }

    @Test
    func stopCancelsInFlightProviderAndSetsCancelledState() async throws {
        let provider = FakeCLIProvider(mode: .blocking)
        let viewModel = try makeViewModel(provider: provider)
        viewModel.inputPrompt = "Improve this prompt."

        #expect(await AppAsyncTestSupport.waitUntil(condition: { viewModel.canImprove }))
        viewModel.improve()

        #expect(await AppAsyncTestSupport.waitUntil(condition: { viewModel.isRunning }))
        viewModel.stop()

        #expect(viewModel.status == .cancelled)
        #expect(viewModel.statusMessage == "Cancelled")
        #expect(provider.cancelCallCount > 0)
    }

    private func makeViewModel(
        guidesCatalogStore: GuidesCatalogStore? = nil,
        provider: FakeCLIProvider
    ) throws -> PromptImproverViewModel {
        let codexExecutable = try AppTestSupport.makeExecutableScript(
            name: "codex",
            script: "#!/bin/sh\nexit 0\n",
            prefix: "ViewModelExecutable"
        )

        let discoveryRunner = StubLocalCommandRunner(defaultResult: LocalCommandResult(
            stdout: "",
            stderr: "",
            status: 1,
            timedOut: false,
            launchErrorDescription: nil
        ))
        let discovery = CLIDiscovery(
            fileManager: .default,
            homeDirectoryPath: NSHomeDirectory(),
            localCommandRunner: discoveryRunner,
            baseCandidatesByTool: [
                .codex: [codexExecutable.path],
                .claude: []
            ]
        )

        let healthRunner = StubLocalCommandRunner(defaultResult: LocalCommandResult(
            stdout: "codex-cli 0.200.0\n",
            stderr: "",
            status: 0,
            timedOut: false,
            launchErrorDescription: nil
        ))
        let healthCheck = CLIHealthCheck(localCommandRunner: healthRunner, commandTimeout: 0.01)

        let settingsStore = EngineSettingsStore(
            fileURL: try AppTestSupport.makeTemporaryDirectory(prefix: "ViewModelSettings")
                .appendingPathComponent("settings.json")
        )
        let resolvedGuidesStore: GuidesCatalogStore
        if let guidesCatalogStore {
            resolvedGuidesStore = guidesCatalogStore
        } else {
            resolvedGuidesStore = GuidesCatalogStore(
                fileURL: try AppTestSupport.makeTemporaryDirectory(prefix: "ViewModelGuides")
                    .appendingPathComponent("model-mapping.json")
            )
        }

        let capabilityStore = ToolCapabilityCacheStore(
            fileURL: try AppTestSupport.makeTemporaryDirectory(prefix: "ViewModelCapabilities")
                .appendingPathComponent("cli-discovery-cache.json"),
            detector: StubCapabilityDetector()
        )

        let templates = Templates(bundle: .main, fallbackRoot: AppTestSupport.templateRootURL())
        let workspaceManager = WorkspaceManager(templates: templates)
        let guideManager = GuideDocumentManager(templates: templates)

        return PromptImproverViewModel(
            discovery: discovery,
            healthCheck: healthCheck,
            workspaceManager: workspaceManager,
            engineSettingsStore: settingsStore,
            capabilityCacheStore: capabilityStore,
            guidesCatalogStore: resolvedGuidesStore,
            guideDocumentManager: guideManager,
            providerFactory: { _, _ in provider }
        )
    }
}

private final class StubLocalCommandRunner: LocalCommandRunning {
    private let defaultResult: LocalCommandResult

    init(defaultResult: LocalCommandResult) {
        self.defaultResult = defaultResult
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval
    ) -> LocalCommandResult {
        defaultResult
    }
}

private struct StubCapabilityDetector: ToolCapabilityDetecting {
    func makeSignature(tool: Tool, executableURL: URL, versionString: String?) -> ToolBinarySignature? {
        ToolBinarySignature(
            tool: tool,
            path: executableURL.path,
            versionString: versionString ?? "",
            mtime: 0,
            size: 0,
            lastCheckedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func detectCapabilities(tool: Tool, executableURL: URL, signature: ToolBinarySignature) -> ToolCapabilities {
        ToolCapabilities(
            supportsModelFlag: true,
            supportsEffortConfig: true,
            supportedEffortValues: EngineEffort.allCases
        )
    }
}

private final class FakeCLIProvider: CLIProvider {
    enum Mode {
        case complete(String)
        case failed(PromptImproverError)
        case blocking
    }

    private let mode: Mode
    private let isCancelled = LockedBool()
    private(set) var cancelCallCount = 0

    init(mode: Mode) {
        self.mode = mode
    }

    func run(request: RunRequest, workspace: WorkspaceHandle) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            switch mode {
            case .complete(let value):
                continuation.yield(.delta("partial"))
                continuation.yield(.completed(value))
                continuation.finish()
            case .failed(let error):
                continuation.yield(.failed(error))
                continuation.finish(throwing: error)
            case .blocking:
                Task {
                    while !isCancelled.value {
                        try? await Task.sleep(nanoseconds: 10_000_000)
                    }
                    continuation.yield(.cancelled)
                    continuation.finish(throwing: PromptImproverError.cancelled)
                }
            }
        }
    }

    func cancel() {
        cancelCallCount += 1
        isCancelled.setTrue()
    }
}

private final class LockedBool: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func setTrue() {
        lock.lock()
        flag = true
        lock.unlock()
    }
}
