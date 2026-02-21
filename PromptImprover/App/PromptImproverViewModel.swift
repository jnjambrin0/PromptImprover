import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class PromptImproverViewModel: ObservableObject {
    @Published var inputPrompt: String = ""
    @Published var outputPrompt: String = ""
    @Published var selectedTool: Tool = .codex
    @Published var selectedTargetModel: TargetModel = .gpt52
    @Published var status: RunStatus = .idle
    @Published var statusMessage: String = "Idle"
    @Published var errorMessage: String?
    @Published private(set) var availabilityByTool: [Tool: CLIAvailability] = [:]
    @Published private(set) var capabilitiesByTool: [Tool: ToolCapabilities] = [:]
    @Published private(set) var capabilityEntriesByTool: [Tool: CachedToolCapabilities] = [:]
    @Published private(set) var isRecheckingCapabilitiesByTool: [Tool: Bool] = [:]

    @Published private(set) var engineSettings: EngineSettings

    private let discovery: CLIDiscovery
    private let healthCheck: CLIHealthCheck
    private let workspaceManager: WorkspaceManager
    private let engineSettingsStore: EngineSettingsStore
    private let capabilityCacheStore: ToolCapabilityCacheStore
    private let diagnosticsQueue = DispatchQueue(label: "PromptImprover.Diagnostics", qos: .utility)
    private let settingsPersistenceQueue = DispatchQueue(label: "PromptImprover.EngineSettingsPersistence", qos: .utility)

    private var runningTask: Task<Void, Never>?
    private var currentProvider: CLIProvider?

    init(
        discovery: CLIDiscovery = CLIDiscovery(),
        healthCheck: CLIHealthCheck = CLIHealthCheck(),
        workspaceManager: WorkspaceManager = WorkspaceManager(),
        engineSettingsStore: EngineSettingsStore = EngineSettingsStore(),
        capabilityCacheStore: ToolCapabilityCacheStore = ToolCapabilityCacheStore()
    ) {
        self.discovery = discovery
        self.healthCheck = healthCheck
        self.workspaceManager = workspaceManager
        self.engineSettingsStore = engineSettingsStore
        self.capabilityCacheStore = capabilityCacheStore
        self.engineSettings = engineSettingsStore.load()
        refreshAvailability()
    }

    var isRunning: Bool {
        status == .running
    }

    var selectedToolAvailability: CLIAvailability? {
        availabilityByTool[selectedTool]
    }

    var selectedToolCapabilities: ToolCapabilities? {
        capabilitiesByTool[selectedTool]
    }

    var improveDisabledReason: String? {
        if inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a prompt to improve."
        }

        guard let availability = selectedToolAvailability else {
            return "Checking tool availability..."
        }

        if !availability.installed {
            return availability.healthMessage ?? selectedTool.missingInstallMessage
        }

        return nil
    }

    var canImprove: Bool {
        !isRunning && improveDisabledReason == nil
    }

    func refreshAvailability() {
        refreshAvailability(for: Tool.allCases, forceCapabilityRefresh: false)
    }

    func recheckCapabilities(for tool: Tool) {
        isRecheckingCapabilitiesByTool[tool] = true
        refreshAvailability(for: [tool], forceCapabilityRefresh: true)
    }

    func isRecheckingCapabilities(for tool: Tool) -> Bool {
        isRecheckingCapabilitiesByTool[tool] == true
    }

    func improve() {
        guard canImprove else {
            return
        }

        runningTask?.cancel()
        currentProvider?.cancel()

        let resolvedEngineModel = engineSettings.resolvedDefaultEngineModel(for: selectedTool)
        let resolvedEngineEffort = resolvedEngineModel.flatMap { model in
            engineSettings.resolvedDefaultEffort(
                for: selectedTool,
                model: model,
                capabilities: capabilitiesByTool[selectedTool]
            )
        }

        Logging.debug(
            "Run config tool=\(selectedTool.rawValue) target=\(selectedTargetModel.rawValue) " +
            "engineModel=\(resolvedEngineModel ?? "none") engineEffort=\(resolvedEngineEffort?.rawValue ?? "none")"
        )

        let request = RunRequest(
            tool: selectedTool,
            targetModel: selectedTargetModel,
            inputPrompt: inputPrompt,
            engineModel: resolvedEngineModel,
            engineEffort: resolvedEngineEffort
        )

        outputPrompt = ""
        errorMessage = nil
        status = .running
        statusMessage = "Running"

        runningTask = Task {
            let workspace: WorkspaceHandle
            do {
                workspace = try workspaceManager.createRunWorkspace(request: request)
            } catch {
                applyError(error)
                return
            }

            defer {
                workspace.cleanup()
                currentProvider = nil
                runningTask = nil
            }

            do {
                let provider = try makeProvider(for: request.tool)
                currentProvider = provider

                for try await event in provider.run(request: request, workspace: workspace) {
                    handle(event)
                }

                if status == .running {
                    status = .error
                    statusMessage = "Error"
                    errorMessage = PromptImproverError.schemaMismatch.localizedDescription
                }
            } catch {
                applyError(error)
            }
        }
    }

    func stop() {
        guard isRunning else {
            return
        }
        currentProvider?.cancel()
        runningTask?.cancel()
        status = .cancelled
        statusMessage = "Cancelled"
    }

    func copyOutputToClipboard() {
        let trimmed = outputPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        _ = pasteboard.setString(trimmed, forType: .string)
    }

    func resolvedEngineModels(for tool: Tool) -> [String] {
        engineSettings.resolvedEngineModels(for: tool)
    }

    func configuredDefaultEngineModel(for tool: Tool) -> String? {
        engineSettings[tool].defaultEngineModel
    }

    func configuredDefaultEffort(for tool: Tool) -> EngineEffort? {
        engineSettings[tool].defaultEffort
    }

    func configuredAllowlistedEfforts(for tool: Tool, model: String) -> [EngineEffort] {
        engineSettings.configuredAllowlistedEfforts(for: tool, model: model)
    }

    func updateOrderedEngineModels(_ models: [String], for tool: Tool) {
        var updated = engineSettings
        updated.setOrderedEngineModels(models, for: tool)
        applyEngineSettings(updated)
    }

    func updateDefaultEngineModel(_ model: String?, for tool: Tool) {
        var updated = engineSettings
        updated.setDefaultEngineModel(model, for: tool)
        applyEngineSettings(updated)
    }

    func updateDefaultEffort(_ effort: EngineEffort?, for tool: Tool) {
        var updated = engineSettings
        updated.setDefaultEffort(effort, for: tool)
        applyEngineSettings(updated)
    }

    func updateAllowlistedEfforts(_ efforts: [EngineEffort], for tool: Tool, model: String) {
        var updated = engineSettings
        updated.setAllowlistedEfforts(efforts, for: tool, model: model)
        applyEngineSettings(updated)
    }

    func resetToolSettingsToDefaults(_ tool: Tool) {
        var updated = engineSettings
        updated.resetToolToDefaults(tool)
        applyEngineSettings(updated)
    }

    func resolvedDefaultEngineModel(for tool: Tool) -> String? {
        engineSettings.resolvedDefaultEngineModel(for: tool)
    }

    func effectiveAllowedEfforts(for tool: Tool, model: String) -> [EngineEffort] {
        engineSettings.effectiveAllowedEfforts(
            for: tool,
            model: model,
            capabilities: capabilitiesByTool[tool]
        )
    }

    func resolvedDefaultEffort(for tool: Tool, model: String) -> EngineEffort? {
        engineSettings.resolvedDefaultEffort(
            for: tool,
            model: model,
            capabilities: capabilitiesByTool[tool]
        )
    }

    func verifyTemplates() -> [String] {
        workspaceManager.verifyTemplateAvailability()
    }

    private func applyEngineSettings(_ updated: EngineSettings) {
        engineSettings = updated
        persistEngineSettings(updated)
    }

    private func persistEngineSettings(_ settings: EngineSettings) {
        let store = UncheckedSendableBox(value: engineSettingsStore)
        settingsPersistenceQueue.async { [store, settings] in
            do {
                try store.value.save(settings)
            } catch {
                Logging.debug("Failed saving engine settings: \(error.localizedDescription)")
            }
        }
    }

    private func refreshAvailability(for tools: [Tool], forceCapabilityRefresh: Bool) {
        var seen: Set<String> = []
        let refreshTools = tools.filter { tool in
            seen.insert(tool.rawValue).inserted
        }
        guard !refreshTools.isEmpty else {
            return
        }

        let discovery = discovery
        let healthCheck = healthCheck
        let capabilityCacheStore = UncheckedSendableBox(value: capabilityCacheStore)

        diagnosticsQueue.async { [weak self] in
            var nextAvailability: [Tool: CLIAvailability] = [:]
            var nextCapabilities: [Tool: ToolCapabilities] = [:]
            var nextEntries: [Tool: CachedToolCapabilities] = [:]

            for tool in refreshTools {
                let executableURL = discovery.resolve(tool: tool)
                let availability = healthCheck.check(tool: tool, executableURL: executableURL)
                nextAvailability[tool] = availability

                if availability.installed,
                   let executableURL = availability.executableURL,
                   let cached = capabilityCacheStore.value.cachedCapabilities(
                        for: tool,
                        executableURL: executableURL,
                        versionString: availability.version,
                        forceRefresh: forceCapabilityRefresh
                   ) {
                    nextEntries[tool] = cached
                    nextCapabilities[tool] = cached.capabilities
                }
            }

            let availabilitySnapshot = nextAvailability
            let capabilitiesSnapshot = nextCapabilities
            let entriesSnapshot = nextEntries

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                var mergedAvailability = self.availabilityByTool
                var mergedCapabilities = self.capabilitiesByTool
                var mergedEntries = self.capabilityEntriesByTool

                for tool in refreshTools {
                    if let availability = availabilitySnapshot[tool] {
                        mergedAvailability[tool] = availability
                    }

                    if let capability = capabilitiesSnapshot[tool] {
                        mergedCapabilities[tool] = capability
                    } else {
                        mergedCapabilities.removeValue(forKey: tool)
                    }

                    if let entry = entriesSnapshot[tool] {
                        mergedEntries[tool] = entry
                    } else {
                        mergedEntries.removeValue(forKey: tool)
                    }

                    if self.isRecheckingCapabilitiesByTool[tool] == true {
                        self.isRecheckingCapabilitiesByTool[tool] = false
                    }
                }

                self.availabilityByTool = mergedAvailability
                self.capabilitiesByTool = mergedCapabilities
                self.capabilityEntriesByTool = mergedEntries
            }
        }
    }

    private func handle(_ event: RunEvent) {
        switch event {
        case .delta(let text):
            outputPrompt.append(text)
        case .completed(let finalPrompt):
            outputPrompt = finalPrompt
            status = .done
            statusMessage = "Done"
        case .failed(let error):
            applyError(error)
        case .cancelled:
            status = .cancelled
            statusMessage = "Cancelled"
        }
    }

    private func makeProvider(for tool: Tool) throws -> CLIProvider {
        guard
            let availability = availabilityByTool[tool],
            availability.installed,
            let executableURL = availability.executableURL
        else {
            throw PromptImproverError.toolNotInstalled(tool)
        }

        switch tool {
        case .codex:
            return CodexProvider(executableURL: executableURL)
        case .claude:
            return ClaudeProvider(executableURL: executableURL)
        }
    }

    private func applyError(_ error: Error) {
        if let appError = error as? PromptImproverError {
            if case .cancelled = appError {
                status = .cancelled
                statusMessage = "Cancelled"
                return
            }
            status = .error
            statusMessage = "Error"
            errorMessage = appError.localizedDescription
            return
        }

        status = .error
        statusMessage = "Error"
        errorMessage = error.localizedDescription
    }
}

private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}
