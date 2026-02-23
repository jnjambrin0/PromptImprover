import Foundation

func fixtureData(named fileName: String, ext: String) throws -> Data {
    let fixtureURL = repositoryRootURL()
        .appendingPathComponent("Tests/Fixtures/\(fileName).\(ext)")
    guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
        throw NSError(
            domain: "Fixture",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing fixture \(fileName).\(ext)"]
        )
    }

    return try Data(contentsOf: fixtureURL)
}

func templateRootURL() -> URL {
    repositoryRootURL()
        .appendingPathComponent("PromptImprover/Resources/templates", isDirectory: true)
}

func repositoryRootURL() -> URL {
    // TestHelpers.swift lives at <repo>/Tests/Unit/TestHelpers.swift.
    URL(fileURLWithPath: #filePath, isDirectory: false)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .standardizedFileURL
}
