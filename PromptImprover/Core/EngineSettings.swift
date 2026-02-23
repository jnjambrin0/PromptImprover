import Foundation

enum EngineEffort: String, CaseIterable, Codable, Hashable {
    case low
    case medium
    case high
    case xhigh
}

struct ToolEngineSettings: Codable, Equatable {
    var defaultEngineModel: String?
    var defaultEffort: EngineEffort?
    var customEngineModels: [String]
    var orderedEngineModels: [String]?
    var perModelEffortAllowlist: [String: [EngineEffort]]

    init(
        defaultEngineModel: String? = nil,
        defaultEffort: EngineEffort? = nil,
        customEngineModels: [String] = [],
        orderedEngineModels: [String]? = nil,
        perModelEffortAllowlist: [String: [EngineEffort]] = [:]
    ) {
        self.defaultEngineModel = ToolEngineSettings.normalizeModelIdentifier(defaultEngineModel)
        self.defaultEffort = defaultEffort
        self.customEngineModels = ToolEngineSettings.orderedUniqueModels(customEngineModels)
        if let orderedEngineModels {
            self.orderedEngineModels = ToolEngineSettings.orderedUniqueModels(orderedEngineModels)
        } else {
            self.orderedEngineModels = nil
        }

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
            orderedEngineModels: orderedEngineModels,
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
            if seen.insert(normalized.lowercased()).inserted {
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
        if let configuredOrder = self[tool].orderedEngineModels {
            return ToolEngineSettings.orderedUniqueModels(configuredOrder)
        }
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
            return EngineSettingsDefaults.defaultSupportedEfforts(for: .claude)
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

    mutating func setOrderedEngineModels(_ models: [String], for tool: Tool) {
        var settings = self[tool]
        settings.orderedEngineModels = ToolEngineSettings.orderedUniqueModels(models)
        settings.reconcileModelDependentFields(with: settings.orderedEngineModels ?? [])
        self[tool] = settings
    }

    mutating func setDefaultEngineModel(_ model: String?, for tool: Tool) {
        var settings = self[tool]
        settings.defaultEngineModel = settings.canonicalModelIdentifier(model, in: resolvedEngineModels(for: tool))
        self[tool] = settings
    }

    mutating func setDefaultEffort(_ effort: EngineEffort?, for tool: Tool) {
        var settings = self[tool]
        settings.defaultEffort = effort
        self[tool] = settings
    }

    mutating func setAllowlistedEfforts(_ efforts: [EngineEffort], for tool: Tool, model: String) {
        var settings = self[tool]
        let resolvedModels = resolvedEngineModels(for: tool)
        guard let canonicalModel = settings.canonicalModelIdentifier(model, in: resolvedModels) else {
            return
        }

        let normalizedEfforts = ToolEngineSettings.orderedUniqueEfforts(efforts)
        if normalizedEfforts.isEmpty {
            settings.perModelEffortAllowlist.removeValue(forKey: canonicalModel)
        } else {
            settings.perModelEffortAllowlist[canonicalModel] = normalizedEfforts
        }

        settings.reconcileModelDependentFields(with: resolvedModels)
        self[tool] = settings
    }

    mutating func resetToolToDefaults(_ tool: Tool) {
        byTool.removeValue(forKey: tool)
    }
}

enum EngineSettingsDefaults {
    static let supportedEffortsByTool: [Tool: [EngineEffort]] = [
        .codex: [.low, .medium, .high, .xhigh],
        .claude: [.low, .medium, .high]
    ]

    static func defaultSupportedEfforts(for tool: Tool) -> [EngineEffort] {
        supportedEffortsByTool[tool] ?? []
    }

    static let seedEngineModels: [Tool: [String]] = [
        .codex: [
            "gpt-5.3-codex",
            "gpt-5.3-codex-spark",
            "gpt-5.2-codex",
            "gpt-5.1-codex-max",
            "gpt-5.2"
        ],
        .claude: [
            "claude-sonnet-4-6",
            "claude-opus-4-6",
            "claude-haiku-4-5"
        ]
    ]
}

private extension ToolEngineSettings {
    mutating func reconcileModelDependentFields(with models: [String]) {
        var canonicalByLowercase: [String: String] = [:]
        for model in models {
            canonicalByLowercase[model.lowercased()] = model
        }

        if let defaultEngineModel {
            self.defaultEngineModel = canonicalByLowercase[defaultEngineModel.lowercased()]
        }

        var reconciledAllowlist: [String: [EngineEffort]] = [:]
        for (rawModel, rawEfforts) in perModelEffortAllowlist {
            guard let canonicalModel = canonicalByLowercase[rawModel.lowercased()] else {
                continue
            }

            let normalizedEfforts = ToolEngineSettings.orderedUniqueEfforts(rawEfforts)
            guard !normalizedEfforts.isEmpty else {
                continue
            }

            if let existing = reconciledAllowlist[canonicalModel] {
                reconciledAllowlist[canonicalModel] = ToolEngineSettings.orderedUniqueEfforts(existing + normalizedEfforts)
            } else {
                reconciledAllowlist[canonicalModel] = normalizedEfforts
            }
        }

        perModelEffortAllowlist = reconciledAllowlist
    }

    func canonicalModelIdentifier(_ model: String?, in models: [String]) -> String? {
        guard let normalized = ToolEngineSettings.normalizeModelIdentifier(model) else {
            return nil
        }
        return models.first { $0.caseInsensitiveCompare(normalized) == .orderedSame }
    }
}
