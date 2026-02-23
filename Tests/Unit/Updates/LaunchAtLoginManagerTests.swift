import Foundation
import ServiceManagement
import Testing
@testable import PromptImproverCore

@MainActor
struct LaunchAtLoginManagerTests {
    @Test
    func initializesFromEnabledStatus() {
        let service = FakeLaunchAtLoginService(status: .enabled)

        let manager = LaunchAtLoginManager(service: service)

        #expect(manager.isEnabled)
        #expect(manager.status == .enabled)
        #expect(manager.message == nil)
        #expect(manager.errorMessage == nil)
    }

    @Test
    func initializesRequiresApprovalStateAsEnabledWithGuidance() {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)

        let manager = LaunchAtLoginManager(service: service)

        #expect(manager.isEnabled)
        #expect(manager.status == .requiresApproval)
        #expect(manager.message?.contains("awaiting approval") == true)
    }

    @Test
    func mapsNotFoundToUnavailableState() {
        let service = FakeLaunchAtLoginService(status: .notFound)

        let manager = LaunchAtLoginManager(service: service)

        #expect(manager.isEnabled == false)
        #expect(manager.status == .unavailable)
        #expect(manager.message != nil)
    }

    @Test
    func enablingRegistersAndRefreshesState() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.onRegister = { service.status = .enabled }

        let manager = LaunchAtLoginManager(service: service)
        manager.setEnabled(true)

        #expect(service.registerCallCount == 1)
        #expect(manager.status == .enabled)
        #expect(manager.isEnabled)
        #expect(manager.errorMessage == nil)
    }

    @Test
    func alreadyRegisteredErrorIsTreatedAsSuccess() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        service.nextRegisterError = NSError(domain: "ServiceManagement", code: kSMErrorAlreadyRegistered)

        let manager = LaunchAtLoginManager(service: service)
        manager.setEnabled(true)

        #expect(service.registerCallCount == 1)
        #expect(manager.status == .enabled)
        #expect(manager.errorMessage == nil)
    }

    @Test
    func launchDeniedKeepsApprovalGuidanceWithoutError() {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)
        service.nextRegisterError = NSError(domain: "ServiceManagement", code: kSMErrorLaunchDeniedByUser)

        let manager = LaunchAtLoginManager(service: service)
        manager.setEnabled(true)

        #expect(manager.status == .requiresApproval)
        #expect(manager.message?.contains("Login Items") == true)
        #expect(manager.errorMessage == nil)
    }

    @Test
    func disablingUnregistersAndClearsEnabledState() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        service.onUnregister = { service.status = .notRegistered }

        let manager = LaunchAtLoginManager(service: service)
        manager.setEnabled(false)

        #expect(service.unregisterCallCount == 1)
        #expect(manager.status == .disabled)
        #expect(manager.isEnabled == false)
    }

    @Test
    func genericErrorsSurfaceFriendlyMessage() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.nextRegisterError = NSError(domain: "test", code: 99, userInfo: [NSLocalizedDescriptionKey: "boom"])

        let manager = LaunchAtLoginManager(service: service)
        manager.setEnabled(true)

        #expect(manager.status == .disabled)
        #expect(manager.errorMessage?.contains("Could not enable Open on Startup.") == true)
        #expect(manager.errorMessage?.contains("boom") == true)
    }

    @Test
    func openSystemSettingsDelegatesToService() {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)

        let manager = LaunchAtLoginManager(service: service)
        manager.openSystemSettings()

        #expect(service.openSystemSettingsCallCount == 1)
    }

    @Test
    func refreshClearsPriorErrorMessage() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.nextRegisterError = NSError(domain: "test", code: 7, userInfo: [NSLocalizedDescriptionKey: "failed"])

        let manager = LaunchAtLoginManager(service: service)
        manager.setEnabled(true)
        #expect(manager.errorMessage != nil)

        manager.refresh()
        #expect(manager.errorMessage == nil)
    }
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginServiceControlling {
    var status: LaunchAtLoginServiceStatus
    var registerCallCount: Int = 0
    var unregisterCallCount: Int = 0
    var openSystemSettingsCallCount: Int = 0

    var nextRegisterError: Error?
    var nextUnregisterError: Error?
    var onRegister: (() -> Void)?
    var onUnregister: (() -> Void)?

    init(status: LaunchAtLoginServiceStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let nextRegisterError {
            self.nextRegisterError = nil
            throw nextRegisterError
        }
        onRegister?()
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let nextUnregisterError {
            self.nextUnregisterError = nil
            throw nextUnregisterError
        }
        onUnregister?()
    }

    func openSystemSettingsLoginItems() {
        openSystemSettingsCallCount += 1
    }
}
