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

    private let discovery: CLIDiscovery
    private let healthCheck: CLIHealthCheck
    private let workspaceManager: WorkspaceManager

    private var runningTask: Task<Void, Never>?
    private var currentProvider: CLIProvider?

    init(
        discovery: CLIDiscovery = CLIDiscovery(),
        healthCheck: CLIHealthCheck = CLIHealthCheck(),
        workspaceManager: WorkspaceManager = WorkspaceManager()
    ) {
        self.discovery = discovery
        self.healthCheck = healthCheck
        self.workspaceManager = workspaceManager
        refreshAvailability()
    }

    var isRunning: Bool {
        status == .running
    }

    var selectedToolAvailability: CLIAvailability? {
        availabilityByTool[selectedTool]
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
        var next: [Tool: CLIAvailability] = [:]
        for tool in Tool.allCases {
            let url = discovery.resolve(tool: tool)
            let availability = healthCheck.check(tool: tool, executableURL: url)
            next[tool] = availability
        }
        availabilityByTool = next
    }

    func improve() {
        guard canImprove else {
            return
        }

        runningTask?.cancel()
        currentProvider?.cancel()

        let request = RunRequest(
            tool: selectedTool,
            targetModel: selectedTargetModel,
            inputPrompt: inputPrompt
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

    func verifyTemplates() -> [String] {
        workspaceManager.verifyTemplateAvailability()
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
