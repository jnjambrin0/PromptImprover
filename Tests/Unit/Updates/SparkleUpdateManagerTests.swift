import Foundation
import Testing
@testable import PromptImproverCore

@MainActor
struct SparkleUpdateManagerTests {
    @Test
    func preferenceBindingsRoundTripToUpdater() {
        let updater = FakeSparkleUpdaterController()
        let manager = SparkleUpdateManager(
            updater: updater,
            installLocationManager: FakeInstallLocationManager(),
            promptStateStore: FakeMovePromptStateStore()
        )

        manager.automaticallyChecksForUpdates = false
        manager.automaticallyDownloadsUpdates = true

        #expect(updater.automaticallyChecksForUpdates == false)
        #expect(updater.automaticallyDownloadsUpdates == true)
    }

    @Test
    func checkForUpdatesRoutesToUpdater() {
        let updater = FakeSparkleUpdaterController()
        updater.hasStartedUpdater = true
        let manager = SparkleUpdateManager(
            updater: updater,
            installLocationManager: FakeInstallLocationManager(),
            promptStateStore: FakeMovePromptStateStore()
        )

        manager.checkForUpdates()

        #expect(updater.checkForUpdatesCallCount == 1)
    }

    @Test
    func managerDoesNotRetainItselfThroughObservation() {
        let updater = FakeSparkleUpdaterController()

        weak var weakManager: SparkleUpdateManager?
        do {
            let manager = SparkleUpdateManager(
                updater: updater,
                installLocationManager: FakeInstallLocationManager(),
                promptStateStore: FakeMovePromptStateStore()
            )
            weakManager = manager
        }

        #expect(weakManager == nil)
    }

    @Test
    func movePromptShowsBeforeStartingUpdaterWhenInstallIsNotUpdatable() async {
        let updater = FakeSparkleUpdaterController()
        let installManager = FakeInstallLocationManager()
        installManager.installState = .notInApplications(readOnly: true, translocated: false)
        let promptStateStore = FakeMovePromptStateStore()
        promptStateStore.forceShouldPrompt = true

        let manager = SparkleUpdateManager(
            updater: updater,
            installLocationManager: installManager,
            promptStateStore: promptStateStore,
            infoValueProvider: validSparkleInfoValueProvider,
            movePromptDelayNanoseconds: 0
        )

        manager.evaluateInstallLocationOnLaunch()
        await Task.yield()

        #expect(manager.isMovePromptPresented == true)
        #expect(updater.startUpdaterCallCount == 0)
        #expect(updater.hasStartedUpdater == false)
    }

    @Test
    func deferringMovePromptStartsUpdater() async {
        let updater = FakeSparkleUpdaterController()
        let installManager = FakeInstallLocationManager()
        installManager.installState = .notInApplications(readOnly: false, translocated: false)
        let promptStateStore = FakeMovePromptStateStore()
        promptStateStore.forceShouldPrompt = true

        let manager = SparkleUpdateManager(
            updater: updater,
            installLocationManager: installManager,
            promptStateStore: promptStateStore,
            infoValueProvider: validSparkleInfoValueProvider,
            movePromptDelayNanoseconds: 0
        )

        manager.evaluateInstallLocationOnLaunch()
        await Task.yield()
        manager.deferMovePrompt()

        #expect(manager.isMovePromptPresented == false)
        #expect(updater.startUpdaterCallCount == 1)
        #expect(updater.hasStartedUpdater == true)
        #expect(promptStateStore.markedVersions.count == 1)
    }

    @Test
    func manualCheckShowsMovePromptInsteadOfCheckingWhenPromptIsPending() {
        let updater = FakeSparkleUpdaterController()
        let installManager = FakeInstallLocationManager()
        installManager.installState = .notInApplications(readOnly: false, translocated: false)
        let promptStateStore = FakeMovePromptStateStore()
        promptStateStore.forceShouldPrompt = true

        let manager = SparkleUpdateManager(
            updater: updater,
            installLocationManager: installManager,
            promptStateStore: promptStateStore
        )

        manager.evaluateInstallLocationOnLaunch()
        manager.checkForUpdates()

        #expect(manager.isMovePromptPresented == true)
        #expect(updater.checkForUpdatesCallCount == 0)
        #expect(updater.startUpdaterCallCount == 0)
    }

    @Test
    func invalidSparkleConfigurationIsExposedWithoutStartingUpdater() {
        let updater = FakeSparkleUpdaterController()
        let installManager = FakeInstallLocationManager()
        installManager.installState = .updatable

        let manager = SparkleUpdateManager(
            updater: updater,
            installLocationManager: installManager,
            promptStateStore: FakeMovePromptStateStore(),
            infoValueProvider: { key in
                switch key {
                case "CFBundleVersion":
                    return "1"
                case "SUFeedURL":
                    return "http://insecure-feed.local/appcast.xml"
                case "SUPublicEDKey":
                    return "invalid"
                default:
                    return nil
                }
            },
            movePromptDelayNanoseconds: 0
        )

        manager.evaluateInstallLocationOnLaunch()

        #expect(manager.updaterConfigurationMessage != nil)
        #expect(manager.canCheckForUpdates == false)
        #expect(updater.startUpdaterCallCount == 0)
        #expect(updater.hasStartedUpdater == false)
    }
}

private func validSparkleInfoValueProvider(for key: String) -> Any? {
    switch key {
    case "CFBundleVersion":
        return "1"
    case "SUFeedURL":
        return "https://example.com/appcast.xml"
    case "SUPublicEDKey":
        return "A9j5LwwY+Qw7dRQtPQQ/N/6YCd5/56DT6jazquGKx/s="
    default:
        return nil
    }
}

@MainActor
private final class FakeSparkleUpdaterController: SparkleUpdaterControlling {
    var hasStartedUpdater: Bool = false
    var canCheckForUpdates: Bool = true
    var automaticallyChecksForUpdates: Bool = true
    var automaticallyDownloadsUpdates: Bool = false
    var allowsAutomaticUpdates: Bool = true

    var startUpdaterCallCount: Int = 0
    var checkForUpdatesCallCount: Int = 0
    private var handlers: [() -> Void] = []

    func startUpdater() {
        startUpdaterCallCount += 1
        hasStartedUpdater = true
    }

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }

    func observeStateChanges(_ handler: @escaping @MainActor () -> Void) -> AnyObject {
        handlers.append(handler)
        return NSObject()
    }
}

@MainActor
private final class FakeInstallLocationManager: InstallLocationManaging {
    var installState: InstallState = .updatable
    var moveCallCount: Int = 0

    func evaluateInstallState() -> InstallState {
        installState
    }

    func moveAndRelaunchIfNeeded() async throws -> URL {
        moveCallCount += 1
        return URL(fileURLWithPath: "/Applications/PromptImprover.app")
    }
}

private final class FakeMovePromptStateStore: MovePromptStateStoring {
    var forceShouldPrompt: Bool?
    private(set) var markedVersions: [String] = []
    private var handledVersions: Set<String> = []

    func shouldPrompt(for appVersion: String) -> Bool {
        if let forceShouldPrompt {
            return forceShouldPrompt
        }
        return !handledVersions.contains(appVersion)
    }

    func markPrompted(for appVersion: String) {
        handledVersions.insert(appVersion)
        markedVersions.append(appVersion)
    }
}
