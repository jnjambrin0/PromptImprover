import SwiftUI

@main
struct PromptImproverApp: App {
    @StateObject private var viewModel = PromptImproverViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel)
        }

        Settings {
            SettingsRootView(viewModel: viewModel)
        }
    }
}
