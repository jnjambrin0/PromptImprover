import Combine
import Foundation
import Sparkle

@MainActor
final class SparkleUpdaterBridge: SparkleUpdaterControlling {
    private let controller: SPUStandardUpdaterController
    private var hasStarted = false

    init(
        startingUpdater: Bool = false,
        updaterDelegate: (any SPUUpdaterDelegate)? = nil,
        userDriverDelegate: (any SPUStandardUserDriverDelegate)? = nil
    ) {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: userDriverDelegate
        )
        self.hasStarted = startingUpdater
    }

    var hasStartedUpdater: Bool {
        hasStarted
    }

    var canCheckForUpdates: Bool {
        guard hasStarted else {
            return false
        }
        return controller.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    var allowsAutomaticUpdates: Bool {
        controller.updater.allowsAutomaticUpdates
    }

    func startUpdater() {
        guard !hasStarted else {
            return
        }

        controller.startUpdater()
        hasStarted = true
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    func observeStateChanges(_ handler: @escaping @MainActor () -> Void) -> AnyObject {
        _ = handler
        return NSObject()
    }
}

@MainActor
final class SparkleUpdateManager: SparkleUpdateManaging {
    @Published private(set) var canCheckForUpdates: Bool = false
    @Published var automaticallyChecksForUpdates: Bool = false {
        didSet {
            guard !isRefreshingFromUpdater else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            refreshUpdaterState()
        }
    }
    @Published var automaticallyDownloadsUpdates: Bool = false {
        didSet {
            guard !isRefreshingFromUpdater else { return }
            updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
            refreshUpdaterState()
        }
    }
    @Published private(set) var allowsAutomaticUpdates: Bool = false
    @Published private(set) var installState: InstallState = .updatable
    @Published private(set) var installWarningMessage: String?
    @Published private(set) var updaterConfigurationMessage: String?
    @Published var isMovePromptPresented: Bool = false

    private let updater: any SparkleUpdaterControlling
    private let installLocationManager: any InstallLocationManaging
    private let promptStateStore: any MovePromptStateStoring
    private let bundle: Bundle
    private let infoValueProvider: (String) -> Any?
    private let movePromptDelayNanoseconds: UInt64

    private var isRefreshingFromUpdater = false
    private var hasEvaluatedInstallLocation = false
    private var pendingPromptVersion: String?
    private var observationToken: AnyObject?
    private var movePromptTask: Task<Void, Never>?

    init(
        updater: (any SparkleUpdaterControlling)? = nil,
        installLocationManager: (any InstallLocationManaging)? = nil,
        promptStateStore: any MovePromptStateStoring = MovePromptStateStore(),
        bundle: Bundle = .main,
        infoValueProvider: ((String) -> Any?)? = nil,
        movePromptDelayNanoseconds: UInt64 = 700_000_000
    ) {
        self.updater = updater ?? SparkleUpdaterBridge()
        self.installLocationManager = installLocationManager ?? InstallLocationManager()
        self.promptStateStore = promptStateStore
        self.bundle = bundle
        self.infoValueProvider = infoValueProvider ?? { key in
            bundle.object(forInfoDictionaryKey: key)
        }
        self.movePromptDelayNanoseconds = movePromptDelayNanoseconds
        self.observationToken = self.updater.observeStateChanges { [weak self] in
            self?.refreshUpdaterState()
        }

        refreshUpdaterState()
    }

    deinit {
        movePromptTask?.cancel()
    }

    func checkForUpdates() {
        if shouldPromptBeforeManualUpdateCheck() {
            presentMovePromptForCurrentVersion()
            return
        }

        startUpdaterIfNeeded()
        guard updater.hasStartedUpdater else {
            return
        }

        updater.checkForUpdates()
        refreshUpdaterState()
    }

    func evaluateInstallLocationOnLaunch() {
        guard !hasEvaluatedInstallLocation else {
            return
        }
        hasEvaluatedInstallLocation = true

        let state = installLocationManager.evaluateInstallState()
        applyInstallState(state)
        let appVersion = currentBuildVersion

        switch state {
        case .updatable:
            startUpdaterIfNeeded()
        case .notInApplications:
            if promptStateStore.shouldPrompt(for: appVersion) {
                scheduleMovePrompt(for: appVersion)
            } else {
                startUpdaterIfNeeded()
            }
        case .moveInProgress, .moveFailed:
            break
        }
    }

    func moveToApplicationsAndRelaunch() {
        movePromptTask?.cancel()
        installState = .moveInProgress
        installWarningMessage = "Moving app to Applications and relaunching..."

        Task { [weak self] in
            guard let self else { return }

            do {
                _ = try await self.installLocationManager.moveAndRelaunchIfNeeded()
                self.markPromptHandledForCurrentVersion()
                self.setMovePromptPresented(false)
            } catch {
                self.applyMoveFailure(message: error.localizedDescription)
            }
        }
    }

    func deferMovePrompt() {
        markPromptHandledForCurrentVersion()
        startUpdaterIfNeeded()
        isMovePromptPresented = false
    }

    private var currentBuildVersion: String {
        if let version = infoValueProvider("CFBundleVersion") as? String,
           !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return version
        }
        return "0"
    }

    private func shouldPromptBeforeManualUpdateCheck() -> Bool {
        guard case .notInApplications = installState else {
            return false
        }
        return promptStateStore.shouldPrompt(for: currentBuildVersion)
    }

    private func presentMovePromptForCurrentVersion() {
        pendingPromptVersion = currentBuildVersion
        movePromptTask?.cancel()
        isMovePromptPresented = true
    }

    private func startUpdaterIfNeeded() {
        guard !updater.hasStartedUpdater else {
            refreshUpdaterState()
            return
        }

        if let configurationIssue = validateUpdaterConfiguration() {
            updaterConfigurationMessage = configurationIssue
            canCheckForUpdates = false
            return
        }

        updater.startUpdater()
        updaterConfigurationMessage = nil
        refreshUpdaterState()
    }

    private func validateUpdaterConfiguration() -> String? {
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "this app"

        guard let feedURLString = (infoValueProvider("SUFeedURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !feedURLString.isEmpty else {
            return "Missing Sparkle SUFeedURL in Info.plist for \(appName)."
        }

        guard let feedURL = URL(string: feedURLString),
              feedURL.scheme?.lowercased() == "https" else {
            return "Invalid Sparkle SUFeedURL (\(feedURLString)). Use an HTTPS URL."
        }

        guard let publicKey = (infoValueProvider("SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !publicKey.isEmpty else {
            return "Missing Sparkle SUPublicEDKey in Info.plist for \(appName)."
        }

        guard let keyData = Data(base64Encoded: publicKey), keyData.count == 32 else {
            return "Invalid Sparkle SUPublicEDKey in Info.plist. Expected base64 ed25519 public key."
        }

        return nil
    }

    private func refreshUpdaterState() {
        isRefreshingFromUpdater = true
        canCheckForUpdates = updater.canCheckForUpdates
        allowsAutomaticUpdates = updater.allowsAutomaticUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        isRefreshingFromUpdater = false
    }

    private func applyInstallState(_ state: InstallState) {
        installState = state
        installWarningMessage = warningMessage(for: state)
    }

    private func scheduleMovePrompt(for appVersion: String) {
        pendingPromptVersion = appVersion
        movePromptTask?.cancel()
        let promptDelay = movePromptDelayNanoseconds
        movePromptTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: promptDelay)
            guard !Task.isCancelled else { return }
            self?.presentMovePromptIfNeeded()
        }
    }

    private func presentMovePromptIfNeeded() {
        guard case .notInApplications = installState else {
            return
        }
        isMovePromptPresented = true
    }

    private func markPromptHandledForCurrentVersion() {
        let version = pendingPromptVersion ?? currentBuildVersion
        promptStateStore.markPrompted(for: version)
        pendingPromptVersion = nil
    }

    private func setMovePromptPresented(_ isPresented: Bool) {
        isMovePromptPresented = isPresented
    }

    private func applyMoveFailure(message: String) {
        installState = .moveFailed(message)
        installWarningMessage = message
        isMovePromptPresented = false
    }

    private func warningMessage(for state: InstallState) -> String? {
        switch state {
        case .updatable:
            return nil
        case let .notInApplications(readOnly, translocated):
            var details: [String] = [
                "PromptImprover is running outside Applications. Sparkle updates are most reliable from /Applications or ~/Applications."
            ]
            if readOnly {
                details.append("Current volume is read-only.")
            }
            if translocated {
                details.append("Current launch appears translocated.")
            }
            return details.joined(separator: " ")
        case .moveInProgress:
            return "Moving app to Applications and relaunching..."
        case let .moveFailed(message):
            return "Move failed: \(message)"
        }
    }
}
