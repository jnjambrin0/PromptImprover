import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: PromptImproverViewModel

    private var showOutput: Bool {
        viewModel.isRunning || viewModel.hasOutput
    }

    var body: some View {
        VStack(spacing: 0) {
            composerArea
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 20)

            if let errorMessage = viewModel.errorMessage {
                ErrorBannerView(
                    message: errorMessage,
                    onDismiss: { viewModel.errorMessage = nil }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .animation(.easeInOut(duration: 0.25), value: viewModel.errorMessage)
            }

            BottomBarView(
                selectedTool: $viewModel.selectedTool,
                selectedTargetSlug: $viewModel.selectedTargetSlug,
                outputModels: viewModel.outputModels,
                isRunning: viewModel.isRunning,
                canImprove: viewModel.canImprove,
                onImprove: viewModel.improve,
                onStop: viewModel.stop
            )
        }
        .frame(
            minWidth: 480,
            minHeight: showOutput ? 320 : 220,
            maxHeight: showOutput ? 560 : 250
        )
        .toolbar(.hidden, for: .windowToolbar)
        .overlay {
            if viewModel.isRunning {
                NeonBorderView(cornerRadius: 10)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showOutput)
        .animation(.easeInOut(duration: 0.4), value: viewModel.isRunning)
    }

    @ViewBuilder
    private var composerArea: some View {
        if showOutput {
            VStack(spacing: 0) {
                InputEditorView(
                    text: $viewModel.inputPrompt,
                    disabledReason: viewModel.improveDisabledReason,
                    showDisabledReason: false
                )
                .frame(minHeight: 80, maxHeight: 140)

                Spacer()
                    .frame(height: 8)

                OutputEditorView(
                    output: viewModel.outputPrompt,
                    onCopy: viewModel.copyOutputToClipboard
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        } else {
            VStack(spacing: 0) {
                InputEditorView(
                    text: $viewModel.inputPrompt,
                    disabledReason: viewModel.improveDisabledReason,
                    showDisabledReason: true
                )
                .frame(minHeight: 120, maxHeight: 160)
            }
        }
    }
}

#Preview {
    RootView(viewModel: PromptImproverViewModel())
}
