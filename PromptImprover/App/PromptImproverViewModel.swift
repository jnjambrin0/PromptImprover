import AppKit
import Combine
import Foundation
import SwiftUI
import os

@MainActor
final class PromptImproverViewModel: ObservableObject {
    @Published var inputPrompt: String = ""
    @Published var outputPrompt: String = ""
    @Published var selectedTool: Tool = .codex
    @Published var selectedTargetSlug: String = ""
    @Published var status: RunStatus = .idle
    @Published var statusMessage: String = "Idle"
    @Published var errorMessage: String?
    @Published private(set) var availabilityByTool: [Tool: CLIAvailability] = [:]
    @Published private(set) var capabilitiesByTool: [Tool: ToolCapabilities] = [:]
    @Published private(set) var capabilityEntriesByTool: [Tool: CachedToolCapabilities] = [:]
    @Published private(set) var isRecheckingCapabilitiesByTool: [Tool: Bool] = [:]

    @Published private(set) var engineSettings: EngineSettings
    @Published private(set) var guidesCatalog: GuidesCatalog

    private let discovery: CLIDiscovery
    private let healthCheck: CLIHealthCheck
    private let workspaceManager: WorkspaceManager
    private let engineSettingsStore: EngineSettingsStore
    private let capabilityCacheStore: ToolCapabilityCacheStore
    private let guidesCatalogStore: GuidesCatalogStore
    private let guideDocumentManager: any GuideDocumentManaging
    private let providerFactory: (Tool, URL) -> CLIProvider
    private let diagnosticsQueue = DispatchQueue(label: "PromptImprover.Diagnostics", qos: .utility)
    private let settingsPersistenceQueue = DispatchQueue(label: "PromptImprover.EngineSettingsPersistence", qos: .utility)
    private let guidesPersistenceQueue = DispatchQueue(label: "PromptImprover.GuidesPersistence", qos: .utility)

    private var runningTask: Task<Void, Never>?
    private var currentProvider: CLIProvider?

    init(
        discovery: CLIDiscovery = CLIDiscovery(),
        healthCheck: CLIHealthCheck = CLIHealthCheck(),
        workspaceManager: WorkspaceManager = WorkspaceManager(),
        engineSettingsStore: EngineSettingsStore = EngineSettingsStore(),
        capabilityCacheStore: ToolCapabilityCacheStore = ToolCapabilityCacheStore(),
        guidesCatalogStore: GuidesCatalogStore = GuidesCatalogStore(),
        guideDocumentManager: any GuideDocumentManaging = GuideDocumentManager(),
        providerFactory: @escaping (Tool, URL) -> CLIProvider = PromptImproverViewModel.defaultProviderFactory
    ) {
        self.discovery = discovery
        self.healthCheck = healthCheck
        self.workspaceManager = workspaceManager
        self.engineSettingsStore = engineSettingsStore
        self.capabilityCacheStore = capabilityCacheStore
        self.guidesCatalogStore = guidesCatalogStore
        self.guideDocumentManager = guideDocumentManager
        self.providerFactory = providerFactory

        let storageLayout = AppStorageLayout.bestEffort()
        do {
            try storageLayout.ensureRequiredDirectories()
        } catch {
            StorageLogger.logger.error("Failed creating required storage directories. error=\(error.localizedDescription)")
        }

        self.engineSettings = engineSettingsStore.load()
        let loadedCatalog = guidesCatalogStore.load().reconciled()
        self.guidesCatalog = loadedCatalog
        self.selectedTargetSlug = loadedCatalog.outputModels.first?.slug ?? ""
        refreshAvailability()
    }

    var isRunning: Bool {
        status == .running
    }

    var hasOutput: Bool {
        !outputPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedToolAvailability: CLIAvailability? {
        availabilityByTool[selectedTool]
    }

    var selectedToolCapabilities: ToolCapabilities? {
        capabilitiesByTool[selectedTool]
    }

    var outputModels: [OutputModel] {
        guidesCatalog.outputModels
    }

    var guides: [GuideDoc] {
        guidesCatalog.guides
    }

    var improveDisabledReason: String? {
        if inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a prompt to improve."
        }

        if guidesCatalog.outputModels.isEmpty {
            return "Add at least one target output model in Settings → Guides."
        }

        if selectedOutputModel() == nil {
            return "Select a valid target output model."
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

        guard let outputModel = selectedOutputModel() else {
            applyError(PromptImproverError.guideManagementFailed("No valid target output model is selected."))
            return
        }
        if guidesCatalog.outputModel(slug: selectedTargetSlug) == nil {
            selectedTargetSlug = outputModel.slug
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
            "Run config tool=\(selectedTool.rawValue) target=\(outputModel.slug) " +
            "engineModel=\(resolvedEngineModel ?? "none") engineEffort=\(resolvedEngineEffort?.rawValue ?? "none")"
        )

        let request = RunRequest(
            tool: selectedTool,
            targetSlug: outputModel.slug,
            targetDisplayName: outputModel.displayName,
            mappedGuides: guidesCatalog.orderedGuides(forOutputSlug: outputModel.slug),
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

    func normalizedOutputModelSlug(from raw: String?) -> String? {
        GuidesCatalog.normalizeSlug(raw)
    }

    func outputModel(forSlug slug: String) -> OutputModel? {
        guidesCatalog.outputModel(slug: slug)
    }

    func orderedGuides(forOutputSlug slug: String) -> [GuideDoc] {
        guidesCatalog.orderedGuides(forOutputSlug: slug)
    }

    func unassignedGuides(forOutputSlug slug: String) -> [GuideDoc] {
        let assigned = Set(orderedGuides(forOutputSlug: slug).map { $0.id.lowercased() })
        return guidesCatalog.guides.filter { !assigned.contains($0.id.lowercased()) }
    }

    @discardableResult
    func addOutputModel(displayName: String, slug: String) throws -> OutputModel {
        var updated = guidesCatalog
        do {
            let model = try updated.addOutputModel(displayName: displayName, slug: slug)
            applyGuidesCatalog(updated, preferredSelectedSlug: model.slug)
            return model
        } catch {
            throw mapGuidesError(error)
        }
    }

    @discardableResult
    func updateOutputModel(existingSlug: String, displayName: String, slug: String) throws -> OutputModel {
        var updated = guidesCatalog
        do {
            let model = try updated.updateOutputModel(existingSlug: existingSlug, displayName: displayName, slug: slug)
            applyGuidesCatalog(updated, preferredSelectedSlug: model.slug)
            return model
        } catch {
            throw mapGuidesError(error)
        }
    }

    @discardableResult
    func deleteOutputModel(slug: String) -> OutputModel? {
        var updated = guidesCatalog
        let removed = updated.removeOutputModel(slug: slug)
        applyGuidesCatalog(updated)
        return removed
    }

    func assignGuide(_ guideID: String, toOutputModel slug: String) throws {
        var updated = guidesCatalog
        do {
            try updated.appendGuide(guideID, toOutputModel: slug)
            applyGuidesCatalog(updated, preferredSelectedSlug: slug)
        } catch {
            throw mapGuidesError(error)
        }
    }

    func unassignGuide(_ guideID: String, fromOutputModel slug: String) throws {
        var updated = guidesCatalog
        do {
            try updated.removeGuide(guideID, fromOutputModel: slug)
            applyGuidesCatalog(updated, preferredSelectedSlug: slug)
        } catch {
            throw mapGuidesError(error)
        }
    }

    func moveGuideUp(_ guideID: String, inOutputModel slug: String) throws {
        let ordered = guidesCatalog.orderedGuides(forOutputSlug: slug)
        guard let index = ordered.firstIndex(where: { $0.id.caseInsensitiveCompare(guideID) == .orderedSame }),
              index > 0 else {
            return
        }

        var updated = guidesCatalog
        do {
            try updated.moveGuide(forOutputModel: slug, from: index, to: index - 1)
            applyGuidesCatalog(updated, preferredSelectedSlug: slug)
        } catch {
            throw mapGuidesError(error)
        }
    }

    func moveGuideDown(_ guideID: String, inOutputModel slug: String) throws {
        let ordered = guidesCatalog.orderedGuides(forOutputSlug: slug)
        guard let index = ordered.firstIndex(where: { $0.id.caseInsensitiveCompare(guideID) == .orderedSame }),
              index < ordered.count - 1 else {
            return
        }

        var updated = guidesCatalog
        do {
            try updated.moveGuide(forOutputModel: slug, from: index, to: index + 1)
            applyGuidesCatalog(updated, preferredSelectedSlug: slug)
        } catch {
            throw mapGuidesError(error)
        }
    }

    @discardableResult
    func importGuide(from sourceURL: URL) throws -> GuideDoc {
        let imported = try guideDocumentManager.importGuide(from: sourceURL)
        var updated = guidesCatalog
        updated.upsertGuide(imported)
        applyGuidesCatalog(updated)
        return imported
    }

    func deleteGuide(id: String) throws {
        guard let existing = guidesCatalog.guide(id: id) else {
            return
        }

        guard !existing.isBuiltIn else {
            throw PromptImproverError.guideManagementFailed("Built-in guides are read-only and cannot be deleted.")
        }

        try guideDocumentManager.deleteUserGuideFileIfPresent(for: existing)

        var updated = guidesCatalog
        do {
            _ = try updated.deleteGuide(id: id)
            applyGuidesCatalog(updated)
        } catch {
            throw mapGuidesError(error)
        }
    }

    func loadGuideText(id: String) throws -> String {
        guard let existing = guidesCatalog.guide(id: id) else {
            throw PromptImproverError.guideManagementFailed("Guide not found.")
        }

        do {
            return try guideDocumentManager.loadText(for: existing)
        } catch {
            throw mapGuidesError(error)
        }
    }

    @discardableResult
    func beginGuideEdit(id: String) throws -> GuideDoc {
        guard let existing = guidesCatalog.guide(id: id) else {
            throw PromptImproverError.guideManagementFailed("Guide not found.")
        }

        do {
            let editable = try guideDocumentManager.ensureEditableGuide(existing)
            var updated = guidesCatalog
            updated.upsertGuide(editable)
            applyGuidesCatalog(updated)
            return editable
        } catch {
            throw mapGuidesError(error)
        }
    }

    @discardableResult
    func saveGuideText(id: String, text: String) throws -> GuideDoc {
        guard let existing = guidesCatalog.guide(id: id) else {
            throw PromptImproverError.guideManagementFailed("Guide not found.")
        }

        do {
            let saved = try guideDocumentManager.saveText(text, for: existing)
            var updated = guidesCatalog
            updated.upsertGuide(saved)
            try applyGuidesCatalogSynchronously(updated)
            return saved
        } catch {
            throw mapGuidesError(error)
        }
    }

    @discardableResult
    func revertGuideToBuiltIn(id: String) throws -> GuideDoc {
        guard let existing = guidesCatalog.guide(id: id) else {
            throw PromptImproverError.guideManagementFailed("Guide not found.")
        }

        do {
            let reverted = try guideDocumentManager.revertBuiltInFork(for: existing)
            var updated = guidesCatalog
            updated.upsertGuide(reverted)
            try applyGuidesCatalogSynchronously(updated)
            return reverted
        } catch {
            throw mapGuidesError(error)
        }
    }

    func guideHasFork(id: String) -> Bool {
        guard let existing = guidesCatalog.guide(id: id), existing.isBuiltIn else {
            return false
        }
        return guideDocumentManager.hasFork(for: existing)
    }

    func resetBuiltInOutputModelsAndMappings() {
        var updated = guidesCatalog
        updated.resetBuiltInsPreservingUserEntries()
        applyGuidesCatalog(updated)
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

    private func applyGuidesCatalog(_ updated: GuidesCatalog, preferredSelectedSlug: String? = nil) {
        let reconciled = updated.reconciled()
        guidesCatalog = reconciled
        selectedTargetSlug = resolvedTargetSelection(in: reconciled, preferredSelectedSlug: preferredSelectedSlug)
        persistGuidesCatalog(reconciled)
    }

    private func applyGuidesCatalogSynchronously(_ updated: GuidesCatalog, preferredSelectedSlug: String? = nil) throws {
        let reconciled = updated.reconciled()
        try guidesCatalogStore.save(reconciled)
        guidesCatalog = reconciled
        selectedTargetSlug = resolvedTargetSelection(in: reconciled, preferredSelectedSlug: preferredSelectedSlug)
    }

    private func persistGuidesCatalog(_ catalog: GuidesCatalog) {
        let store = UncheckedSendableBox(value: guidesCatalogStore)
        guidesPersistenceQueue.async { [store, catalog] in
            do {
                try store.value.save(catalog)
            } catch {
                Logging.debug("Failed saving guides catalog: \(error.localizedDescription)")
            }
        }
    }

    private func resolvedTargetSelection(in catalog: GuidesCatalog, preferredSelectedSlug: String?) -> String {
        if let preferredSelectedSlug,
           let resolvedPreferred = catalog.outputModel(slug: preferredSelectedSlug) {
            return resolvedPreferred.slug
        }

        if let current = catalog.outputModel(slug: selectedTargetSlug) {
            return current.slug
        }

        return catalog.outputModels.first?.slug ?? ""
    }

    private func selectedOutputModel() -> OutputModel? {
        if let selected = guidesCatalog.outputModel(slug: selectedTargetSlug) {
            return selected
        }
        return guidesCatalog.outputModels.first
    }

    private func mapGuidesError(_ error: Error) -> PromptImproverError {
        if let appError = error as? PromptImproverError {
            return appError
        }

        if let catalogError = error as? GuidesCatalogError {
            switch catalogError {
            case .invalidDisplayName:
                return .guideManagementFailed("Output model display name cannot be empty.")
            case .invalidSlug:
                return .guideManagementFailed("Output model slug is invalid. Use letters, numbers, and separators.")
            case .duplicateSlug:
                return .guideManagementFailed("An output model with this slug already exists.")
            case .outputModelNotFound:
                return .guideManagementFailed("Output model not found.")
            case .guideNotFound:
                return .guideManagementFailed("Guide not found.")
            case .cannotDeleteBuiltInGuide:
                return .guideManagementFailed("Built-in guides are read-only and cannot be deleted.")
            case .invalidGuideOrder:
                return .guideManagementFailed("Guide reorder request is invalid.")
            }
        }

        return .guideManagementFailed(error.localizedDescription)
    }

    private func refreshAvailability(for tools: [Tool], forceCapabilityRefresh: Bool) {
        var seen: Set<String> = []
        let refreshTools = tools.filter { tool in
            seen.insert(tool.rawValue).inserted
        }
        guard !refreshTools.isEmpty else {
            return
        }

        let discovery = UncheckedSendableBox(value: discovery)
        let healthCheck = UncheckedSendableBox(value: healthCheck)
        let capabilityCacheStore = UncheckedSendableBox(value: capabilityCacheStore)

        diagnosticsQueue.async { [weak self] in
            var nextAvailability: [Tool: CLIAvailability] = [:]
            var nextCapabilities: [Tool: ToolCapabilities] = [:]
            var nextEntries: [Tool: CachedToolCapabilities] = [:]

            for tool in refreshTools {
                let executableURL = discovery.value.resolve(tool: tool)
                let availability = healthCheck.value.check(tool: tool, executableURL: executableURL)
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

        return providerFactory(tool, executableURL)
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

extension PromptImproverViewModel {
    nonisolated static func defaultProviderFactory(tool: Tool, executableURL: URL) -> CLIProvider {
        switch tool {
        case .codex:
            return CodexProvider(executableURL: executableURL)
        case .claude:
            return ClaudeProvider(executableURL: executableURL)
        }
    }
}

private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}
