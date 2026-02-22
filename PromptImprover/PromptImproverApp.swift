import SwiftUI

@main
struct PromptImproverApp: App {
    @StateObject private var viewModel = PromptImproverViewModel()
    @StateObject private var updateManager = SparkleUpdateManager()

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel, updateManager: updateManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 250)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateManager.checkForUpdates()
                }
                .disabled(!updateManager.canCheckForUpdates)
            }
        }

        Settings {
            SettingsRootView(viewModel: viewModel, updateManager: updateManager)
        }
    }
}
