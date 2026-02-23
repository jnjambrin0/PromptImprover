import Foundation

struct WorkspaceHandle {
    let path: URL
    let guideFilenamesInOrder: [String]

    var inputPromptPath: URL { path.appendingPathComponent("INPUT_PROMPT.txt") }
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
    private let temporaryRoot: URL
    private let guideDocumentManager: any GuideDocumentManaging

    init(
        fileManager: FileManager = .default,
        templates: Templates = Templates(),
        temporaryRoot: URL? = nil,
        guideDocumentManager: (any GuideDocumentManaging)? = nil
    ) {
        self.fileManager = fileManager
        self.templates = templates
        self.temporaryRoot = temporaryRoot ?? AppStorageLayout.bestEffort(fileManager: fileManager).temporaryRoot
        self.guideDocumentManager = guideDocumentManager
            ?? GuideDocumentManager(fileManager: fileManager, templates: templates)
    }

    func createRunWorkspace(request: RunRequest) throws -> WorkspaceHandle {
        let root = temporaryRoot
            .appendingPathComponent("run-\(UUID().uuidString)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            try writeInputFile(request: request, root: root)
            try copyTemplates(for: request.tool, into: root)
            let guideFilenames = try copyMappedGuides(request: request, into: root)
            try writeRunConfig(targetSlug: request.targetSlug, guideFilenamesInOrder: guideFilenames, root: root)
            try applyClaudeEffortConfigurationIfNeeded(request: request, root: root)
            return WorkspaceHandle(path: root, guideFilenamesInOrder: guideFilenames)
        } catch {
            try? fileManager.removeItem(at: root)
            throw PromptImproverError.workspaceFailure(error.localizedDescription)
        }
    }

    func verifyTemplateAvailability() -> [String] {
        templates.verifyAllAccessible()
    }

    private func writeInputFile(request: RunRequest, root: URL) throws {
        let normalizedInputPrompt = normalizedInputPromptText(request.inputPrompt)
        try normalizedInputPrompt.write(to: root.appendingPathComponent("INPUT_PROMPT.txt"), atomically: true, encoding: .utf8)
    }

    private func writeRunConfig(targetSlug: String, guideFilenamesInOrder: [String], root: URL) throws {
        let runConfig = WorkspaceRunConfig(
            targetSlug: targetSlug,
            guideFilenamesInOrder: guideFilenamesInOrder
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(runConfig)
        try data.write(to: root.appendingPathComponent("RUN_CONFIG.json"), options: .atomic)
    }

    private func copyTemplates(for tool: Tool, into root: URL) throws {
        for asset in TemplateAsset.runtimeAssets(for: tool) {
            let destination = root.appendingPathComponent(asset.relativePath)
            let directory = destination.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let data = try templates.data(for: asset)
            try data.write(to: destination, options: .atomic)
        }
    }

    private func copyMappedGuides(request: RunRequest, into root: URL) throws -> [String] {
        guard !request.mappedGuides.isEmpty else {
            return []
        }

        let guidesRoot = root.appendingPathComponent("guides", isDirectory: true)
        try fileManager.createDirectory(at: guidesRoot, withIntermediateDirectories: true)

        var guideFilenamesInOrder: [String] = []
        for (index, guide) in request.mappedGuides.enumerated() {
            let safeGuideID = sanitizedFilenameComponent(guide.id)
            let relativePath = String(format: "guides/%03d-%@.md", index + 1, safeGuideID)
            let destination = root.appendingPathComponent(relativePath)
            let data = try guideDocumentManager.data(for: guide)
            try data.write(to: destination, options: .atomic)
            guideFilenamesInOrder.append(relativePath)
        }

        return guideFilenamesInOrder
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

    private func sanitizedFilenameComponent(_ raw: String) -> String {
        let replaced = raw.lowercased().map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return "-"
        }

        var normalized = String(replaced)
        normalized = normalized.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return normalized.isEmpty ? "guide" : normalized
    }

    private func normalizedInputPromptText(_ raw: String) -> String {
        let normalizedNewlines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalizedNewlines.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct WorkspaceRunConfig: Codable {
    let targetSlug: String
    let guideFilenamesInOrder: [String]
}
