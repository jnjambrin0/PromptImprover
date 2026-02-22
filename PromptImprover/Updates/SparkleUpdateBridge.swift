import Foundation

@MainActor
protocol SparkleUpdaterControlling: AnyObject {
    var hasStartedUpdater: Bool { get }
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var allowsAutomaticUpdates: Bool { get }

    func startUpdater()
    func checkForUpdates()
    func observeStateChanges(_ handler: @escaping @MainActor () -> Void) -> AnyObject
}

@MainActor
protocol SparkleUpdateManaging: ObservableObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var allowsAutomaticUpdates: Bool { get }
    var installState: InstallState { get }
    var installWarningMessage: String? { get }
    var updaterConfigurationMessage: String? { get }
    var isMovePromptPresented: Bool { get set }

    func checkForUpdates()
    func evaluateInstallLocationOnLaunch()
    func moveToApplicationsAndRelaunch()
    func deferMovePrompt()
}

protocol MovePromptStateStoring {
    func shouldPrompt(for appVersion: String) -> Bool
    func markPrompted(for appVersion: String)
}

struct MovePromptStateStore: MovePromptStateStoring {
    private let userDefaults: UserDefaults
    private let lastHandledVersionKey: String

    init(
        userDefaults: UserDefaults = .standard,
        lastHandledVersionKey: String = "updates.movePrompt.lastHandledVersion"
    ) {
        self.userDefaults = userDefaults
        self.lastHandledVersionKey = lastHandledVersionKey
    }

    func shouldPrompt(for appVersion: String) -> Bool {
        userDefaults.string(forKey: lastHandledVersionKey) != appVersion
    }

    func markPrompted(for appVersion: String) {
        userDefaults.set(appVersion, forKey: lastHandledVersionKey)
    }
}
