import Combine
import Foundation
import ServiceManagement

@MainActor
protocol LaunchAtLoginServiceControlling {
    var status: LaunchAtLoginServiceStatus { get }

    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

enum LaunchAtLoginServiceStatus: Equatable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
    case unknown
}

@MainActor
struct MainAppLaunchAtLoginService: LaunchAtLoginServiceControlling {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LaunchAtLoginServiceStatus {
        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .notRegistered
        case .notFound:
            return .notFound
        @unknown default:
            return .unknown
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
enum LaunchAtLoginStatus: Equatable {
    case enabled
    case requiresApproval
    case disabled
    case unavailable
}

@MainActor
protocol LaunchAtLoginManaging: ObservableObject {
    var isEnabled: Bool { get }
    var status: LaunchAtLoginStatus { get }
    var message: String? { get }
    var errorMessage: String? { get }

    func refresh()
    func setEnabled(_ enabled: Bool)
    func openSystemSettings()
}

@MainActor
final class LaunchAtLoginManager: LaunchAtLoginManaging {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var status: LaunchAtLoginStatus = .disabled
    @Published private(set) var message: String?
    @Published private(set) var errorMessage: String?

    private let service: any LaunchAtLoginServiceControlling

    convenience init() {
        self.init(service: MainAppLaunchAtLoginService())
    }

    init(service: any LaunchAtLoginServiceControlling) {
        self.service = service
        refresh()
    }

    func refresh() {
        errorMessage = nil
        apply(status: service.status)
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            if enabled && isAlreadyRegistered(error) {
                // Treat duplicate registration as success to keep toggle state stable.
            } else if enabled && isLaunchDenied(error) {
                apply(status: .requiresApproval, overrideMessage: Self.requiresApprovalMessage)
                return
            } else {
                errorMessage = makeErrorMessage(for: error, desiredEnabled: enabled)
            }
        }

        apply(status: service.status)
    }

    func openSystemSettings() {
        service.openSystemSettingsLoginItems()
    }

    private func apply(status: LaunchAtLoginServiceStatus, overrideMessage: String? = nil) {
        switch status {
        case .enabled:
            self.status = .enabled
            isEnabled = true
            message = nil
        case .requiresApproval:
            self.status = .requiresApproval
            isEnabled = true
            message = Self.requiresApprovalMessage
        case .notRegistered:
            self.status = .disabled
            isEnabled = false
            message = nil
        case .notFound, .unknown:
            self.status = .unavailable
            isEnabled = false
            message = Self.unavailableMessage
        }

        if let overrideMessage {
            message = overrideMessage
        }
    }

    private func isAlreadyRegistered(_ error: Error) -> Bool {
        (error as NSError).code == kSMErrorAlreadyRegistered
    }

    private func isLaunchDenied(_ error: Error) -> Bool {
        (error as NSError).code == kSMErrorLaunchDeniedByUser
    }

    private func makeErrorMessage(for error: Error, desiredEnabled: Bool) -> String {
        let prefix = desiredEnabled
            ? "Could not enable Open on Startup."
            : "Could not disable Open on Startup."
        let details = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !details.isEmpty, details != "(null)" else {
            return prefix
        }

        return "\(prefix) \(details)"
    }

    private static let requiresApprovalMessage =
        "Open on Startup is awaiting approval in System Settings > General > Login Items."

    private static let unavailableMessage =
        "Open on Startup is unavailable because this app could not be registered as a login item."
}
