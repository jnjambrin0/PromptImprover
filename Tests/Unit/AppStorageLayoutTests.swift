import Foundation
import Testing
@testable import PromptImproverCore

struct AppStorageLayoutTests {
    @Test
    func resolvesAppScopedRootsFromSystemDirectories() throws {
        let appName = "PromptImproverStorageLayout-\(UUID().uuidString)"
        let layout = try makeLayout(appName: appName)
        defer { cleanup(layout) }

        #expect(layout.appSupportRoot.lastPathComponent == appName)
        #expect(layout.cachesRoot.lastPathComponent == appName)
        #expect(layout.temporaryRoot.lastPathComponent == appName)

        #expect(layout.settingsFile.lastPathComponent == "settings.json")
        #expect(layout.modelMappingFile.lastPathComponent == "model-mapping.json")
        #expect(layout.cliDiscoveryCacheFile.lastPathComponent == "cli-discovery-cache.json")
    }

    @Test
    func ensureRequiredDirectoriesCreatesDirectoryTree() throws {
        let appName = "PromptImproverStorageEnsure-\(UUID().uuidString)"
        let layout = try makeLayout(appName: appName)
        defer { cleanup(layout) }

        try layout.ensureRequiredDirectories()

        let requiredDirectories = [
            layout.appSupportRoot,
            layout.guidesRoot,
            layout.builtInGuidesDirectory,
            layout.userGuidesDirectory,
            layout.userGuideForksDirectory,
            layout.diagnosticsDirectory,
            layout.cachesRoot,
            layout.ragIndexDirectory,
            layout.thumbnailsDirectory,
            layout.temporaryRoot,
        ]

        for directory in requiredDirectories {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            #expect(exists)
            #expect(isDirectory.boolValue)
        }
    }

    @Test
    func helperURLFactoriesBuildRelativeLocations() throws {
        let appName = "PromptImproverStorageHelpers-\(UUID().uuidString)"
        let layout = try makeLayout(appName: appName)
        defer { cleanup(layout) }

        #expect(layout.builtInGuideURL(fileName: "A.md") == layout.builtInGuidesDirectory.appendingPathComponent("A.md"))
        #expect(layout.userGuideURL(fileName: "B.md") == layout.userGuidesDirectory.appendingPathComponent("B.md"))
        #expect(layout.cacheFileURL(fileName: "cache.bin") == layout.cachesRoot.appendingPathComponent("cache.bin"))
        #expect(layout.diagnosticsFileURL(fileName: "diag.log") == layout.diagnosticsDirectory.appendingPathComponent("diag.log"))
    }

    private func cleanup(_ layout: AppStorageLayout) {
        try? FileManager.default.removeItem(at: layout.appSupportRoot)
        try? FileManager.default.removeItem(at: layout.cachesRoot)
        try? FileManager.default.removeItem(at: layout.temporaryRoot)
    }

    private func makeLayout(appName: String) throws -> AppStorageLayout {
        let root = try TestSupport.makeTemporaryDirectory(prefix: "StorageLayout")
        let appSupportRoot = root.appendingPathComponent("ApplicationSupport/\(appName)", isDirectory: true)
        let cachesRoot = root.appendingPathComponent("Caches/\(appName)", isDirectory: true)
        let temporaryRoot = root.appendingPathComponent("Temporary/\(appName)", isDirectory: true)
        return AppStorageLayout(
            appSupportRoot: appSupportRoot,
            cachesRoot: cachesRoot,
            temporaryRoot: temporaryRoot
        )
    }
}
