import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var viewModel: PromptImproverViewModel

    var body: some View {
        TabView {
            ModelsSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Models", systemImage: "slider.horizontal.3")
                }

            GuidesSettingsView()
                .tabItem {
                    Label("Guides", systemImage: "book")
                }
        }
        .padding(16)
        .frame(minWidth: 860, minHeight: 560)
    }
}

#Preview {
    SettingsRootView(viewModel: PromptImproverViewModel())
}
