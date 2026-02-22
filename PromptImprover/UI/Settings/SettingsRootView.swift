import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var viewModel: PromptImproverViewModel

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
        }
        .padding(16)
        .frame(minWidth: 1100, minHeight: 700)
    }
}

#Preview {
    SettingsRootView(viewModel: PromptImproverViewModel())
}
