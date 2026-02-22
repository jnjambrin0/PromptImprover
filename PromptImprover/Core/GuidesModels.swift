import Foundation

enum GuidesCatalogError: Error, Equatable {
    case invalidDisplayName
    case invalidSlug
    case duplicateSlug
    case outputModelNotFound
    case guideNotFound
    case cannotDeleteBuiltInGuide
    case invalidGuideOrder
}

struct OutputModel: Identifiable, Codable, Equatable, Hashable {
    var displayName: String
    var slug: String
    var guideIds: [String]

    var id: String { slug }

    init(displayName: String, slug: String, guideIds: [String] = []) {
        self.displayName = OutputModel.normalizeDisplayName(displayName) ?? displayName
        self.slug = slug
        self.guideIds = GuidesCatalog.orderedUniqueGuideIDs(guideIds)
    }

    static func normalizeDisplayName(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct GuideDoc: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var title: String
    var storagePath: String
    var forkStoragePath: String?
    var isBuiltIn: Bool
    var updatedAt: Date
    var hash: String?

    init(
        id: String,
        title: String,
        storagePath: String,
        forkStoragePath: String? = nil,
        isBuiltIn: Bool,
        updatedAt: Date,
        hash: String? = nil
    ) {
        self.id = GuideDoc.normalizeIdentifier(id) ?? id
        self.title = GuideDoc.normalizeTitle(title) ?? title
        self.storagePath = GuideDoc.normalizeStoragePath(storagePath) ?? storagePath
        self.forkStoragePath = GuideDoc.normalizeStoragePath(forkStoragePath)
        self.isBuiltIn = isBuiltIn
        self.updatedAt = updatedAt
        self.hash = hash?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeIdentifier(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizeTitle(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizeStoragePath(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
        return normalized.isEmpty ? nil : normalized
    }
}

struct GuidesCatalog: Codable, Equatable {
    var outputModels: [OutputModel]
    var guides: [GuideDoc]

    init(outputModels: [OutputModel] = [], guides: [GuideDoc] = []) {
        let normalized = GuidesCatalog.normalized(outputModels: outputModels, guides: guides)
        self.outputModels = normalized.outputModels
        self.guides = normalized.guides
    }

    static var `default`: GuidesCatalog {
        GuidesDefaults.defaultCatalog
    }

    func outputModel(slug rawSlug: String?) -> OutputModel? {
        guard let normalizedSlug = GuidesCatalog.normalizeSlug(rawSlug) else {
            return nil
        }

        return outputModels.first { model in
            model.slug.caseInsensitiveCompare(normalizedSlug) == .orderedSame
        }
    }

    func guide(id rawID: String?) -> GuideDoc? {
        guard let normalizedID = GuideDoc.normalizeIdentifier(rawID) else {
            return nil
        }

        return guides.first { guide in
            guide.id.caseInsensitiveCompare(normalizedID) == .orderedSame
        }
    }

    func orderedGuides(forOutputSlug rawSlug: String?) -> [GuideDoc] {
        guard let model = outputModel(slug: rawSlug) else {
            return []
        }

        return model.guideIds.compactMap { requestedID in
            guide(id: requestedID)
        }
    }

    mutating func addOutputModel(displayName: String, slug rawSlug: String) throws -> OutputModel {
        guard let normalizedName = OutputModel.normalizeDisplayName(displayName) else {
            throw GuidesCatalogError.invalidDisplayName
        }
        guard let normalizedSlug = GuidesCatalog.normalizeSlug(rawSlug) else {
            throw GuidesCatalogError.invalidSlug
        }
        guard outputModel(slug: normalizedSlug) == nil else {
            throw GuidesCatalogError.duplicateSlug
        }

        let model = OutputModel(displayName: normalizedName, slug: normalizedSlug, guideIds: [])
        outputModels.append(model)
        self = reconciled()
        return model
    }

    mutating func updateOutputModel(existingSlug: String, displayName: String, slug rawSlug: String) throws -> OutputModel {
        guard let normalizedName = OutputModel.normalizeDisplayName(displayName) else {
            throw GuidesCatalogError.invalidDisplayName
        }
        guard let normalizedSlug = GuidesCatalog.normalizeSlug(rawSlug) else {
            throw GuidesCatalogError.invalidSlug
        }
        guard let targetIndex = outputModels.firstIndex(where: { $0.slug.caseInsensitiveCompare(existingSlug) == .orderedSame }) else {
            throw GuidesCatalogError.outputModelNotFound
        }

        if let existing = outputModels.first(where: { $0.slug.caseInsensitiveCompare(normalizedSlug) == .orderedSame }),
           existing.slug.caseInsensitiveCompare(existingSlug) != .orderedSame {
            throw GuidesCatalogError.duplicateSlug
        }

        outputModels[targetIndex].displayName = normalizedName
        outputModels[targetIndex].slug = normalizedSlug
        self = reconciled()
        guard let updated = outputModel(slug: normalizedSlug) else {
            throw GuidesCatalogError.outputModelNotFound
        }
        return updated
    }

    @discardableResult
    mutating func removeOutputModel(slug: String) -> OutputModel? {
        guard let index = outputModels.firstIndex(where: { $0.slug.caseInsensitiveCompare(slug) == .orderedSame }) else {
            return nil
        }

        let removed = outputModels.remove(at: index)
        self = reconciled()
        return removed
    }

    mutating func upsertGuide(_ guide: GuideDoc) {
        if let index = guides.firstIndex(where: { $0.id.caseInsensitiveCompare(guide.id) == .orderedSame }) {
            guides[index] = guide
        } else {
            guides.append(guide)
        }

        self = reconciled()
    }

    @discardableResult
    mutating func deleteGuide(id: String, allowBuiltIn: Bool = false) throws -> GuideDoc? {
        guard let index = guides.firstIndex(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else {
            return nil
        }

        let guide = guides[index]
        if guide.isBuiltIn && !allowBuiltIn {
            throw GuidesCatalogError.cannotDeleteBuiltInGuide
        }

        guides.remove(at: index)
        removeGuideReferences(id)
        self = reconciled()
        return guide
    }

    mutating func appendGuide(_ guideID: String, toOutputModel slug: String) throws {
        guard guide(id: guideID) != nil else {
            throw GuidesCatalogError.guideNotFound
        }
        guard let index = outputModels.firstIndex(where: { $0.slug.caseInsensitiveCompare(slug) == .orderedSame }) else {
            throw GuidesCatalogError.outputModelNotFound
        }

        if outputModels[index].guideIds.contains(where: { $0.caseInsensitiveCompare(guideID) == .orderedSame }) {
            return
        }
        outputModels[index].guideIds.append(guideID)
        self = reconciled()
    }

    mutating func removeGuide(_ guideID: String, fromOutputModel slug: String) throws {
        guard let index = outputModels.firstIndex(where: { $0.slug.caseInsensitiveCompare(slug) == .orderedSame }) else {
            throw GuidesCatalogError.outputModelNotFound
        }

        outputModels[index].guideIds.removeAll { existing in
            existing.caseInsensitiveCompare(guideID) == .orderedSame
        }
        self = reconciled()
    }

    mutating func moveGuide(forOutputModel slug: String, from sourceIndex: Int, to destinationIndex: Int) throws {
        guard let modelIndex = outputModels.firstIndex(where: { $0.slug.caseInsensitiveCompare(slug) == .orderedSame }) else {
            throw GuidesCatalogError.outputModelNotFound
        }

        var ordered = outputModels[modelIndex].guideIds
        guard ordered.indices.contains(sourceIndex),
              ordered.indices.contains(destinationIndex) else {
            throw GuidesCatalogError.invalidGuideOrder
        }

        let item = ordered.remove(at: sourceIndex)
        ordered.insert(item, at: destinationIndex)
        outputModels[modelIndex].guideIds = ordered
        self = reconciled()
    }

    mutating func removeGuideReferences(_ guideID: String) {
        for index in outputModels.indices {
            outputModels[index].guideIds.removeAll { existing in
                existing.caseInsensitiveCompare(guideID) == .orderedSame
            }
        }
        self = reconciled()
    }

    mutating func resetBuiltInsPreservingUserEntries() {
        let preservedUserGuides = guides.filter { !$0.isBuiltIn }
        let preservedUserOutputModels = outputModels.filter { model in
            !GuidesDefaults.isBuiltInOutputModelSlug(model.slug)
        }

        guides = GuidesDefaults.builtInGuides + preservedUserGuides
        outputModels = GuidesDefaults.builtInOutputModels + preservedUserOutputModels
        self = reconciled()
    }

    func reconciled() -> GuidesCatalog {
        let normalized = GuidesCatalog.normalized(outputModels: outputModels, guides: guides)
        return GuidesCatalog(outputModels: normalized.outputModels, guides: normalized.guides, alreadyNormalized: true)
    }

    static func normalizeSlug(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }

        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else {
            return nil
        }

        let replaced = lowered.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        var slug = String(replaced)
        slug = slug.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return slug.isEmpty ? nil : slug
    }

    static func orderedUniqueGuideIDs(_ guideIDs: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for guideID in guideIDs {
            guard let normalized = GuideDoc.normalizeIdentifier(guideID) else {
                continue
            }

            let key = normalized.lowercased()
            if seen.insert(key).inserted {
                ordered.append(normalized)
            }
        }

        return ordered
    }

    private init(outputModels: [OutputModel], guides: [GuideDoc], alreadyNormalized: Bool) {
        self.outputModels = outputModels
        self.guides = guides
    }

    private static func normalized(outputModels: [OutputModel], guides: [GuideDoc]) -> (outputModels: [OutputModel], guides: [GuideDoc]) {
        var normalizedGuides: [GuideDoc] = []
        var seenGuideIDs: Set<String> = []

        for guide in guides {
            guard
                let normalizedID = GuideDoc.normalizeIdentifier(guide.id),
                let normalizedTitle = GuideDoc.normalizeTitle(guide.title),
                let normalizedPath = GuideDoc.normalizeStoragePath(guide.storagePath)
            else {
                continue
            }

            let key = normalizedID.lowercased()
            guard seenGuideIDs.insert(key).inserted else {
                continue
            }

            normalizedGuides.append(
                GuideDoc(
                    id: normalizedID,
                    title: normalizedTitle,
                    storagePath: normalizedPath,
                    forkStoragePath: GuideDoc.normalizeStoragePath(guide.forkStoragePath),
                    isBuiltIn: guide.isBuiltIn,
                    updatedAt: guide.updatedAt,
                    hash: guide.hash
                )
            )
        }

        let guideIDByLowercase = Dictionary(uniqueKeysWithValues: normalizedGuides.map { ($0.id.lowercased(), $0.id) })

        var normalizedModels: [OutputModel] = []
        var seenSlugs: Set<String> = []

        for model in outputModels {
            guard
                let normalizedDisplayName = OutputModel.normalizeDisplayName(model.displayName),
                let normalizedSlug = GuidesCatalog.normalizeSlug(model.slug)
            else {
                continue
            }

            let slugKey = normalizedSlug.lowercased()
            guard seenSlugs.insert(slugKey).inserted else {
                continue
            }

            let orderedGuideIDs = reconcileGuideIDs(model.guideIds, with: guideIDByLowercase)
            normalizedModels.append(
                OutputModel(
                    displayName: normalizedDisplayName,
                    slug: normalizedSlug,
                    guideIds: orderedGuideIDs
                )
            )
        }

        return (outputModels: normalizedModels, guides: normalizedGuides)
    }

    private static func reconcileGuideIDs(_ guideIDs: [String], with canonicalByLowercaseID: [String: String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for requestedID in guideIDs {
            guard let normalized = GuideDoc.normalizeIdentifier(requestedID) else {
                continue
            }

            let key = normalized.lowercased()
            guard let canonicalID = canonicalByLowercaseID[key] else {
                continue
            }

            if seen.insert(canonicalID.lowercased()).inserted {
                ordered.append(canonicalID)
            }
        }

        return ordered
    }
}

enum GuidesDefaults {
    static let claudeGuideID = "builtin-guide-claude-4-6"
    static let gptGuideID = "builtin-guide-gpt-5-2"
    static let geminiGuideID = "builtin-guide-gemini-3-0"

    static let claudeOutputSlug = "claude-4-6"
    static let gptOutputSlug = "gpt-5-2"
    static let geminiOutputSlug = "gemini-3-0"

    private static let builtInUpdatedAt = Date(timeIntervalSince1970: 1_737_590_400) // 2025-01-20
    private static let builtInTemplateByGuideID: [String: String] = [
        claudeGuideID: "CLAUDE_PROMPT_GUIDE.md",
        gptGuideID: "GPT5.2_PROMPT_GUIDE.md",
        geminiGuideID: "GEMINI3_PROMPT_GUIDE.md",
    ]

    static let builtInGuides: [GuideDoc] = [
        GuideDoc(
            id: claudeGuideID,
            title: "Claude 4.6 Prompt Guide",
            storagePath: "guides/builtin/CLAUDE_PROMPT_GUIDE.md",
            isBuiltIn: true,
            updatedAt: builtInUpdatedAt
        ),
        GuideDoc(
            id: gptGuideID,
            title: "GPT-5.2 Prompt Guide",
            storagePath: "guides/builtin/GPT5.2_PROMPT_GUIDE.md",
            isBuiltIn: true,
            updatedAt: builtInUpdatedAt
        ),
        GuideDoc(
            id: geminiGuideID,
            title: "Gemini 3.0 Prompt Guide",
            storagePath: "guides/builtin/GEMINI3_PROMPT_GUIDE.md",
            isBuiltIn: true,
            updatedAt: builtInUpdatedAt
        )
    ]

    static let builtInOutputModels: [OutputModel] = [
        OutputModel(
            displayName: "Claude 4.6",
            slug: claudeOutputSlug,
            guideIds: [claudeGuideID]
        ),
        OutputModel(
            displayName: "GPT-5.2",
            slug: gptOutputSlug,
            guideIds: [gptGuideID]
        ),
        OutputModel(
            displayName: "Gemini 3.0",
            slug: geminiOutputSlug,
            guideIds: [geminiGuideID]
        )
    ]

    static var defaultCatalog: GuidesCatalog {
        GuidesCatalog(outputModels: builtInOutputModels, guides: builtInGuides)
    }

    static func isBuiltInOutputModelSlug(_ slug: String) -> Bool {
        let normalized = slug.lowercased()
        return builtInOutputModels.contains { model in
            model.slug.lowercased() == normalized
        }
    }

    static func builtInTemplateRelativePath(forGuideID rawGuideID: String) -> String? {
        builtInTemplateByGuideID.first { key, _ in
            key.caseInsensitiveCompare(rawGuideID) == .orderedSame
        }?.value
    }
}
