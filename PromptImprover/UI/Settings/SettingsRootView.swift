import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var viewModel: PromptImproverViewModel
    @ObservedObject var updateManager: SparkleUpdateManager
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager

    var body: some View {
        TabView {
            ModelsSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Models", systemImage: "slider.horizontal.3")
                }

            GuidesSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Guides", systemImage: "book")
                }

            UpdatesSettingsView(
                updateManager: updateManager,
                launchAtLoginManager: launchAtLoginManager
            )
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .padding(16)
        .frame(minWidth: 960, minHeight: 580)
    }
}

#Preview {
    SettingsRootView(
        viewModel: PromptImproverViewModel(),
        updateManager: SparkleUpdateManager(
            updater: SettingsPreviewSparkleUpdaterController(),
            installLocationManager: SettingsPreviewInstallLocationManager()
        ),
        launchAtLoginManager: LaunchAtLoginManager(service: SettingsPreviewLaunchAtLoginService())
    )
}

@MainActor
private final class SettingsPreviewSparkleUpdaterController: SparkleUpdaterControlling {
    var hasStartedUpdater: Bool = true
    var canCheckForUpdates: Bool = true
    var automaticallyChecksForUpdates: Bool = true
    var automaticallyDownloadsUpdates: Bool = false
    var allowsAutomaticUpdates: Bool = true

    func startUpdater() {}
    func checkForUpdates() {}
    func observeStateChanges(_ handler: @escaping @MainActor () -> Void) -> AnyObject {
        _ = handler
        return NSObject()
    }
}

@MainActor
private struct SettingsPreviewInstallLocationManager: InstallLocationManaging {
    func evaluateInstallState() -> InstallState {
        .updatable
    }

    func moveAndRelaunchIfNeeded() async throws -> URL {
        URL(fileURLWithPath: "/Applications/PromptImprover.app")
    }
}

@MainActor
private final class SettingsPreviewLaunchAtLoginService: LaunchAtLoginServiceControlling {
    var status: LaunchAtLoginServiceStatus = .notRegistered

    func register() {
        status = .enabled
    }

    func unregister() {
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {}
}
