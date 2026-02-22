import SwiftUI

@main
struct PromptImproverApp: App {
    @StateObject private var viewModel = PromptImproverViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 250)

        Settings {
            SettingsRootView(viewModel: viewModel)
        }
    }
}
