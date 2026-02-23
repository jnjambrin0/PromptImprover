import Foundation

struct StorageSettingsDocument: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var settingsByTool: [String: ToolEngineSettings]
}

struct StorageModelMappingDocument: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var outputModels: [OutputModel]
    var guides: [GuideDoc]
}
