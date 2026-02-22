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
                .padding(.top, 16)
                .padding(.bottom, 12)

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
        .frame(minWidth: 480, minHeight: 320)
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
                Spacer(minLength: 0)
            }
        }
    }
}

#Preview {
    RootView(viewModel: PromptImproverViewModel())
}
