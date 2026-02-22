import SwiftUI

@main
struct PromptImproverApp: App {
    @StateObject private var viewModel = PromptImproverViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel)
        }
        .defaultSize(width: 520, height: 360)

        Settings {
            SettingsRootView(viewModel: viewModel)
        }
    }
}
