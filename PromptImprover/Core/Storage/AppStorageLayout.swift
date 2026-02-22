import Foundation
import os

struct AppStorageLayout {
    let appSupportRoot: URL
    let cachesRoot: URL
    let temporaryRoot: URL

    let settingsFile: URL
    let modelMappingFile: URL

    let guidesRoot: URL
    let builtInGuidesDirectory: URL
    let userGuidesDirectory: URL
    let userGuideForksDirectory: URL

    let diagnosticsDirectory: URL

    let cliDiscoveryCacheFile: URL
    let ragIndexDirectory: URL
    let thumbnailsDirectory: URL

    init(appName: String = "PromptImprover", fileManager: FileManager = .default) throws {
        let appSupportBase = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let cachesBase = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let temporaryBase = fileManager.temporaryDirectory

        self.init(
            appSupportRoot: appSupportBase.appendingPathComponent(appName, isDirectory: true),
            cachesRoot: cachesBase.appendingPathComponent(appName, isDirectory: true),
            temporaryRoot: temporaryBase.appendingPathComponent(appName, isDirectory: true)
        )
    }

    init(appSupportRoot: URL, cachesRoot: URL, temporaryRoot: URL) {
        self.appSupportRoot = appSupportRoot
        self.cachesRoot = cachesRoot
        self.temporaryRoot = temporaryRoot

        settingsFile = appSupportRoot.appendingPathComponent("settings.json")
        modelMappingFile = appSupportRoot.appendingPathComponent("model-mapping.json")

        guidesRoot = appSupportRoot.appendingPathComponent("guides", isDirectory: true)
        builtInGuidesDirectory = guidesRoot.appendingPathComponent("builtin", isDirectory: true)
        userGuidesDirectory = guidesRoot.appendingPathComponent("user", isDirectory: true)
        userGuideForksDirectory = userGuidesDirectory.appendingPathComponent("forks", isDirectory: true)

        diagnosticsDirectory = appSupportRoot.appendingPathComponent("diagnostics", isDirectory: true)

        cliDiscoveryCacheFile = cachesRoot.appendingPathComponent("cli-discovery-cache.json")
        ragIndexDirectory = cachesRoot.appendingPathComponent("rag-index", isDirectory: true)
        thumbnailsDirectory = cachesRoot.appendingPathComponent("thumbnails", isDirectory: true)
    }

    static func bestEffort(appName: String = "PromptImprover", fileManager: FileManager = .default) -> AppStorageLayout {
        do {
            return try AppStorageLayout(appName: appName, fileManager: fileManager)
        } catch {
            StorageLogger.logger.error(
                "Failed resolving storage directories. Falling back to temporary roots. error=\(error.localizedDescription)"
            )
            let fallbackRoot = fileManager.temporaryDirectory.appendingPathComponent(appName, isDirectory: true)
            return AppStorageLayout(
                appSupportRoot: fallbackRoot.appendingPathComponent("ApplicationSupport", isDirectory: true),
                cachesRoot: fallbackRoot.appendingPathComponent("Caches", isDirectory: true),
                temporaryRoot: fallbackRoot.appendingPathComponent("tmp", isDirectory: true)
            )
        }
    }

    func ensureRequiredDirectories(fileManager: FileManager = .default) throws {
        let requiredDirectories = [
            appSupportRoot,
            guidesRoot,
            builtInGuidesDirectory,
            userGuidesDirectory,
            userGuideForksDirectory,
            diagnosticsDirectory,
            cachesRoot,
            ragIndexDirectory,
            thumbnailsDirectory,
            temporaryRoot,
        ]

        for directory in requiredDirectories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func builtInGuideURL(fileName: String) -> URL {
        builtInGuidesDirectory.appendingPathComponent(fileName)
    }

    func userGuideURL(fileName: String) -> URL {
        userGuidesDirectory.appendingPathComponent(fileName)
    }

    func cacheFileURL(fileName: String) -> URL {
        cachesRoot.appendingPathComponent(fileName)
    }

    func diagnosticsFileURL(fileName: String) -> URL {
        diagnosticsDirectory.appendingPathComponent(fileName)
    }
}
