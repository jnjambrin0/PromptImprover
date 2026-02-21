import Foundation

enum TemplateAsset: CaseIterable {
    case agents
    case claude
    case claudeSettings
    case schema

    var relativePath: String {
        switch self {
        case .agents: return "AGENTS.md"
        case .claude: return "CLAUDE.md"
        case .claudeSettings: return ".claude/settings.json"
        case .schema: return "schema/optimized_prompt.schema.json"
        }
    }
}

struct Templates {
    let bundle: Bundle
    let fallbackRoot: URL?

    init(bundle: Bundle = .main, fallbackRoot: URL? = nil) {
        self.bundle = bundle
        self.fallbackRoot = fallbackRoot
    }

    func data(for asset: TemplateAsset) throws -> Data {
        try data(forRelativePath: asset.relativePath)
    }

    func data(forRelativePath relativePath: String) throws -> Data {
        if let bundled = bundledURL(forRelativePath: relativePath) {
            return try Data(contentsOf: bundled)
        }

        if let fallback = fallbackURL(forRelativePath: relativePath), FileManager.default.fileExists(atPath: fallback.path) {
            return try Data(contentsOf: fallback)
        }

        throw PromptImproverError.workspaceFailure("Missing template: \(relativePath)")
    }

    func verifyAllAccessible() -> [String] {
        var missing: [String] = []
        for asset in TemplateAsset.allCases {
            do {
                _ = try data(for: asset)
            } catch {
                missing.append(asset.relativePath)
            }
        }
        return missing
    }

    private func bundledURL(forRelativePath relativePath: String) -> URL? {
        let nsPath = relativePath as NSString
        let directory = nsPath.deletingLastPathComponent
        let fileName = nsPath.lastPathComponent
        let ext = (fileName as NSString).pathExtension
        let name = (fileName as NSString).deletingPathExtension

        let subdirectory: String
        if directory.isEmpty {
            subdirectory = "templates"
        } else {
            subdirectory = "templates/\(directory)"
        }

        return bundle.url(forResource: name, withExtension: ext.isEmpty ? nil : ext, subdirectory: subdirectory)
    }

    private func fallbackURL(forRelativePath relativePath: String) -> URL? {
        if let fallbackRoot {
            return fallbackRoot.appendingPathComponent(relativePath)
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let defaultRoot = cwd.appendingPathComponent("PromptImprover/Resources/templates", isDirectory: true)
        return defaultRoot.appendingPathComponent(relativePath)
    }
}
