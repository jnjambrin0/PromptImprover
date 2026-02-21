import Foundation

struct WorkspaceHandle {
    let path: URL

    var inputPromptPath: URL { path.appendingPathComponent("INPUT_PROMPT.txt") }
    var targetModelPath: URL { path.appendingPathComponent("TARGET_MODEL.txt") }
    var runConfigPath: URL { path.appendingPathComponent("RUN_CONFIG.json") }
    var schemaPath: URL { path.appendingPathComponent("schema/optimized_prompt.schema.json") }

    func cleanup() {
        do {
            try FileManager.default.removeItem(at: path)
        } catch {
            Logging.debug("Workspace cleanup failed: \(error.localizedDescription)")
        }
    }
}

struct WorkspaceManager {
    private let fileManager: FileManager
    private let templates: Templates

    init(fileManager: FileManager = .default, templates: Templates = Templates()) {
        self.fileManager = fileManager
        self.templates = templates
    }

    func createRunWorkspace(request: RunRequest) throws -> WorkspaceHandle {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PromptImprover", isDirectory: true)
            .appendingPathComponent("run-\(UUID().uuidString)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            try writeRuntimeFiles(request: request, root: root)
            try copyTemplates(into: root)
            try applyClaudeEffortConfigurationIfNeeded(request: request, root: root)
            return WorkspaceHandle(path: root)
        } catch {
            try? fileManager.removeItem(at: root)
            throw PromptImproverError.workspaceFailure(error.localizedDescription)
        }
    }

    func verifyTemplateAvailability() -> [String] {
        templates.verifyAllAccessible()
    }

    private func writeRuntimeFiles(request: RunRequest, root: URL) throws {
        try request.inputPrompt.write(to: root.appendingPathComponent("INPUT_PROMPT.txt"), atomically: true, encoding: .utf8)
        try request.targetModel.displayName.write(to: root.appendingPathComponent("TARGET_MODEL.txt"), atomically: true, encoding: .utf8)

        let runConfig = try JSONEncoder().encode(request)
        try runConfig.write(to: root.appendingPathComponent("RUN_CONFIG.json"), options: .atomic)
    }

    private func copyTemplates(into root: URL) throws {
        for asset in TemplateAsset.allCases {
            let destination = root.appendingPathComponent(asset.relativePath)
            let directory = destination.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let data = try templates.data(for: asset)
            try data.write(to: destination, options: .atomic)
        }
    }

    private func applyClaudeEffortConfigurationIfNeeded(request: RunRequest, root: URL) throws {
        guard request.tool == .claude, let effort = request.engineEffort else {
            return
        }

        let settingsURL = root.appendingPathComponent(".claude/settings.json")
        try fileManager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var settingsObject: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let parsed = try? JSONSerialization.jsonObject(with: data),
           let dict = parsed as? [String: Any] {
            settingsObject = dict
        }

        settingsObject["effortLevel"] = effort.rawValue

        let outputData = try JSONSerialization.data(
            withJSONObject: settingsObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        try outputData.write(to: settingsURL, options: .atomic)
    }
}
