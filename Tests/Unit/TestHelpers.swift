import Foundation

func fixtureData(named fileName: String, ext: String) throws -> Data {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Tests/Fixtures/\(fileName).\(ext)")

    guard FileManager.default.fileExists(atPath: url.path) else {
        throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture \(fileName).\(ext)"])
    }

    return try Data(contentsOf: url)
}

func templateRootURL() -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("PromptImprover/Resources/templates", isDirectory: true)
}
