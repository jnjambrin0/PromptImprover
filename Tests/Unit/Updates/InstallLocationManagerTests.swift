import AppKit
import Foundation
import Testing
@testable import PromptImproverCore

@MainActor
struct InstallLocationManagerTests {
    @Test
    func appInsideSystemApplicationsIsUpdatable() throws {
        let context = try makeContext()
        let appURL = try context.createSourceApp(named: "PromptImprover.app")
        let systemAppURL = context.systemApplications.appendingPathComponent(appURL.lastPathComponent, isDirectory: true)
        try FileManager.default.copyItem(at: appURL, to: systemAppURL)

        let manager = context.makeManager(appBundleURL: systemAppURL)
        #expect(manager.evaluateInstallState() == .updatable)
    }

    @Test
    func appInsideUserApplicationsIsUpdatable() throws {
        let context = try makeContext()
        let appURL = try context.createSourceApp(named: "PromptImprover.app")
        let userAppURL = context.userApplications.appendingPathComponent(appURL.lastPathComponent, isDirectory: true)
        try FileManager.default.copyItem(at: appURL, to: userAppURL)

        let manager = context.makeManager(appBundleURL: userAppURL)
        #expect(manager.evaluateInstallState() == .updatable)
    }

    @Test
    func appOnReadOnlyVolumeIsFlagged() throws {
        let context = try makeContext()
        let source = try context.createSourceApp(named: "PromptImprover.app")

        let manager = context.makeManager(
            appBundleURL: source,
            volumeReadOnlyEvaluator: { _ in true }
        )

        #expect(manager.evaluateInstallState() == .notInApplications(readOnly: true, translocated: false))
    }

    @Test
    func translocatedPathIsFlagged() throws {
        let context = try makeContext()
        let translocated = context.root
            .appendingPathComponent("AppTranslocation", isDirectory: true)
            .appendingPathComponent("PromptImprover.app", isDirectory: true)
        try FileManager.default.createDirectory(at: translocated, withIntermediateDirectories: true)

        let manager = context.makeManager(appBundleURL: translocated)
        #expect(manager.evaluateInstallState() == .notInApplications(readOnly: false, translocated: true))
    }

    @Test
    func moveFallsBackToUserApplicationsWhenSystemIsNotWritable() async throws {
        let context = try makeContext()
        let sourceApp = try context.createSourceApp(named: "PromptImprover.app")

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: context.systemApplications.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: context.systemApplications.path)
        }

        let manager = context.makeManager(appBundleURL: sourceApp)
        let movedURL = try await manager.moveAndRelaunchIfNeeded()

        #expect(movedURL.path.hasPrefix(context.userApplications.path))
        #expect(FileManager.default.fileExists(atPath: movedURL.path))
        #expect(context.workspace.openedApplications.contains(movedURL))
        #expect(context.openCommandLauncher.openedDestinations.isEmpty)
        #expect(context.didTerminate == true)
    }

    @Test
    func successfulWorkspaceRelaunchTerminatesWithoutFallback() async throws {
        let context = try makeContext()
        let sourceApp = try context.createSourceApp(named: "PromptImprover.app")
        let manager = context.makeManager(
            appBundleURL: sourceApp,
            launchedApplicationVerifier: { _, _ in true }
        )

        _ = try await manager.moveAndRelaunchIfNeeded()

        #expect(context.workspace.lastConfiguration?.createsNewApplicationInstance == true)
        #expect(context.openCommandLauncher.openedDestinations.isEmpty)
        #expect(context.didTerminate == true)
    }

    @Test
    func invalidWorkspaceRelaunchUsesFallbackAndDoesNotTerminateWhenFallbackFails() async throws {
        let context = try makeContext()
        let sourceApp = try context.createSourceApp(named: "PromptImprover.app")
        context.openCommandLauncher.shouldSucceed = false

        let manager = context.makeManager(
            appBundleURL: sourceApp,
            launchedApplicationVerifier: { _, _ in false }
        )

        await #expect(throws: InstallLocationManager.Error.self) {
            _ = try await manager.moveAndRelaunchIfNeeded()
        }

        #expect(context.openCommandLauncher.openedDestinations.count == 1)
        #expect(context.didTerminate == false)
    }

    @Test
    func invalidWorkspaceRelaunchUsesFallbackAndTerminatesWhenFallbackSucceeds() async throws {
        let context = try makeContext()
        let sourceApp = try context.createSourceApp(named: "PromptImprover.app")

        let manager = context.makeManager(
            appBundleURL: sourceApp,
            launchedApplicationVerifier: { _, _ in false }
        )

        _ = try await manager.moveAndRelaunchIfNeeded()

        #expect(context.openCommandLauncher.openedDestinations.count == 1)
        #expect(context.didTerminate == true)
    }

    private func makeContext() throws -> InstallLocationTestContext {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PromptImproverInstallLocationTests-\(UUID().uuidString)", isDirectory: true)
        let systemApplications = root.appendingPathComponent("Applications", isDirectory: true)
        let userApplications = root.appendingPathComponent("UserApplications", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)

        try FileManager.default.createDirectory(at: systemApplications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userApplications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

        return InstallLocationTestContext(
            root: root,
            systemApplications: systemApplications,
            userApplications: userApplications,
            sourceRoot: sourceRoot
        )
    }
}

@MainActor
private final class InstallLocationTestContext {
    let root: URL
    let systemApplications: URL
    let userApplications: URL
    let sourceRoot: URL
    let workspace = FakeWorkspaceApplicationLauncher()
    let openCommandLauncher = FakeOpenCommandLauncher()
    var didTerminate = false

    init(root: URL, systemApplications: URL, userApplications: URL, sourceRoot: URL) {
        self.root = root
        self.systemApplications = systemApplications
        self.userApplications = userApplications
        self.sourceRoot = sourceRoot
    }

    func createSourceApp(named name: String) throws -> URL {
        let appURL = sourceRoot.appendingPathComponent(name, isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let infoPlist = contentsURL.appendingPathComponent("Info.plist")
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.jnjambrin0.PromptImprover",
            "CFBundleName": "PromptImprover"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: infoPlist, options: .atomic)

        return appURL
    }

    func makeManager(
        appBundleURL: URL,
        volumeReadOnlyEvaluator: @escaping (URL) -> Bool = { _ in false },
        launchedApplicationVerifier: @escaping (NSRunningApplication, URL) -> Bool = { _, _ in true }
    ) -> InstallLocationManager {
        InstallLocationManager(
            fileManager: .default,
            workspaceLauncher: workspace,
            openCommandLauncher: openCommandLauncher,
            appBundleURL: appBundleURL,
            expectedBundleIdentifier: "com.jnjambrin0.PromptImprover",
            terminateCurrentApp: { [weak self] in
                self?.didTerminate = true
            },
            systemApplicationsDirectoryURL: systemApplications,
            userApplicationsDirectoryURL: userApplications,
            volumeReadOnlyEvaluator: volumeReadOnlyEvaluator,
            launchedApplicationVerifier: launchedApplicationVerifier
        )
    }
}

@MainActor
private final class FakeWorkspaceApplicationLauncher: WorkspaceApplicationLaunching {
    var openedApplications: [URL] = []
    var lastConfiguration: NSWorkspace.OpenConfiguration?
    var resultRunningApp: NSRunningApplication? = NSRunningApplication.current
    var resultError: (any Error)?

    func openApplication(
        at url: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completionHandler: @escaping @Sendable (NSRunningApplication?, (any Error)?) -> Void
    ) {
        openedApplications.append(url)
        lastConfiguration = configuration
        completionHandler(resultRunningApp, resultError)
    }
}

private struct FakeOpenCommandError: LocalizedError {
    let errorDescription: String? = "Fallback open command failed."
}

private final class FakeOpenCommandLauncher: OpenCommandLaunching {
    var openedDestinations: [URL] = []
    var shouldSucceed = true

    func openNewInstance(at destination: URL) throws {
        openedDestinations.append(destination)
        if !shouldSucceed {
            throw FakeOpenCommandError()
        }
    }
}
