import Foundation

enum EngineEffort: String, CaseIterable, Codable, Hashable {
    case low
    case medium
    case high
}

struct ToolEngineSettings: Codable, Equatable {
    var defaultEngineModel: String?
    var defaultEffort: EngineEffort?
    var customEngineModels: [String]
    var perModelEffortAllowlist: [String: [EngineEffort]]

    init(
        defaultEngineModel: String? = nil,
        defaultEffort: EngineEffort? = nil,
        customEngineModels: [String] = [],
        perModelEffortAllowlist: [String: [EngineEffort]] = [:]
    ) {
        self.defaultEngineModel = ToolEngineSettings.normalizeModelIdentifier(defaultEngineModel)
        self.defaultEffort = defaultEffort
        self.customEngineModels = ToolEngineSettings.orderedUniqueModels(customEngineModels)

        var normalizedAllowlist: [String: [EngineEffort]] = [:]
        for (rawModel, rawEfforts) in perModelEffortAllowlist {
            guard let model = ToolEngineSettings.normalizeModelIdentifier(rawModel) else {
                continue
            }

            let efforts = ToolEngineSettings.orderedUniqueEfforts(rawEfforts)
            guard !efforts.isEmpty else {
                continue
            }

            normalizedAllowlist[model] = efforts
        }
        self.perModelEffortAllowlist = normalizedAllowlist
    }

    func normalized() -> ToolEngineSettings {
        ToolEngineSettings(
            defaultEngineModel: defaultEngineModel,
            defaultEffort: defaultEffort,
            customEngineModels: customEngineModels,
            perModelEffortAllowlist: perModelEffortAllowlist
        )
    }

    func explicitAllowlist(for model: String) -> [EngineEffort]? {
        guard let normalizedModel = ToolEngineSettings.normalizeModelIdentifier(model) else {
            return nil
        }

        if let direct = perModelEffortAllowlist[normalizedModel] {
            return ToolEngineSettings.orderedUniqueEfforts(direct)
        }

        if let (_, value) = perModelEffortAllowlist.first(where: { lhs, _ in
            lhs.caseInsensitiveCompare(normalizedModel) == .orderedSame
        }) {
            return ToolEngineSettings.orderedUniqueEfforts(value)
        }

        return nil
    }

    static func normalizeModelIdentifier(_ model: String?) -> String? {
        guard let model else {
            return nil
        }
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func orderedUniqueModels(_ models: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for model in models {
            guard let normalized = normalizeModelIdentifier(model) else {
                continue
            }
            if seen.insert(normalized).inserted {
                ordered.append(normalized)
            }
        }
        return ordered
    }

    static func orderedUniqueEfforts(_ values: [EngineEffort]) -> [EngineEffort] {
        var seen: Set<EngineEffort> = []
        var ordered: [EngineEffort] = []
        for value in values {
            if seen.insert(value).inserted {
                ordered.append(value)
            }
        }
        return ordered
    }
}

struct EngineSettings: Codable, Equatable {
    var byTool: [Tool: ToolEngineSettings]

    init(byTool: [Tool: ToolEngineSettings] = [:]) {
        self.byTool = byTool.mapValues { $0.normalized() }
    }

    static let `default` = EngineSettings()

    subscript(tool: Tool) -> ToolEngineSettings {
        get { byTool[tool] ?? ToolEngineSettings() }
        set { byTool[tool] = newValue.normalized() }
    }

    func resolvedEngineModels(for tool: Tool) -> [String] {
        let seeded = EngineSettingsDefaults.seedEngineModels[tool] ?? []
        let custom = self[tool].customEngineModels
        return ToolEngineSettings.orderedUniqueModels(seeded + custom)
    }

    func resolvedDefaultEngineModel(for tool: Tool) -> String? {
        let settings = self[tool]
        let resolvedModels = resolvedEngineModels(for: tool)

        if let configured = ToolEngineSettings.normalizeModelIdentifier(settings.defaultEngineModel),
           resolvedModels.contains(where: { $0.caseInsensitiveCompare(configured) == .orderedSame }) {
            return configured
        }

        return resolvedModels.first
    }

    func configuredAllowlistedEfforts(for tool: Tool, model: String) -> [EngineEffort] {
        let settings = self[tool]
        if let explicit = settings.explicitAllowlist(for: model) {
            return explicit
        }

        if tool == .claude, model.range(of: "opus", options: [.caseInsensitive]) != nil {
            return EngineEffort.allCases
        }

        return []
    }

    func effectiveAllowedEfforts(for tool: Tool, model: String, capabilities: ToolCapabilities?) -> [EngineEffort] {
        guard let capabilities, capabilities.supportsEffortConfig else {
            return []
        }

        let allowlisted = configuredAllowlistedEfforts(for: tool, model: model)
        let supported = ToolEngineSettings.orderedUniqueEfforts(capabilities.supportedEffortValues)
        guard !allowlisted.isEmpty, !supported.isEmpty else {
            return []
        }

        let supportedSet = Set(supported)
        return allowlisted.filter { supportedSet.contains($0) }
    }

    func resolvedDefaultEffort(for tool: Tool, model: String, capabilities: ToolCapabilities?) -> EngineEffort? {
        let configured = self[tool].defaultEffort
        guard let configured else {
            return nil
        }

        let allowed = effectiveAllowedEfforts(for: tool, model: model, capabilities: capabilities)
        return allowed.contains(configured) ? configured : nil
    }
}

enum EngineSettingsDefaults {
    static let seedEngineModels: [Tool: [String]] = [
        .codex: [
            "gpt-5",
            "gpt-5-mini",
            "o3"
        ],
        .claude: [
            "claude-sonnet-4-6",
            "claude-opus-4-6",
            "claude-opus-4-1"
        ]
    ]
}
