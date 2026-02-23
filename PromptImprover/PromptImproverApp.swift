import AppKit
import SwiftUI

@main
struct PromptImproverApp: App {
    @NSApplicationDelegateAdaptor(PromptImproverAppDelegate.self) private var appDelegate
    @StateObject private var viewModel = PromptImproverViewModel()
    @StateObject private var updateManager = SparkleUpdateManager()
    @StateObject private var launchAtLoginManager = LaunchAtLoginManager()

    var body: some Scene {
        WindowGroup(id: MainWindowController.mainWindowSceneID) {
            RootView(viewModel: viewModel, updateManager: updateManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 250)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateManager.checkForUpdates()
                }
                .disabled(!updateManager.canCheckForUpdates)
            }
        }

        Settings {
            SettingsRootView(
                viewModel: viewModel,
                updateManager: updateManager,
                launchAtLoginManager: launchAtLoginManager
            )
        }

        MenuBarExtra {
            MenuBarMenuView()
        } label: {
            MenuBarIconLabelView()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarMenuView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Button("Open") {
                MainWindowController.shared.toggleMainWindow {
                    openWindow(id: MainWindowController.mainWindowSceneID)
                }
            }
            Button("Settings…") {
                openSettings()
            }
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }
}

private struct MenuBarIconLabelView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image("ToolbarIcon")
            .onAppear {
                MainWindowController.shared.setFallbackOpenWindowAction {
                    openWindow(id: MainWindowController.mainWindowSceneID)
                }
            }
    }
}
