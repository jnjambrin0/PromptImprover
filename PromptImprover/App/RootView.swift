import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: PromptImproverViewModel

    private var showOutput: Bool {
        viewModel.isRunning || viewModel.hasOutput
    }

    var body: some View {
        VStack(spacing: 0) {
            composerArea
                .padding(.horizontal, 48)
                .padding(.top, 24)
                .padding(.bottom, 12)

            if let errorMessage = viewModel.errorMessage {
                ErrorBannerView(
                    message: errorMessage,
                    onDismiss: { viewModel.errorMessage = nil }
                )
                .padding(.horizontal, 48)
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
        .frame(minWidth: 640, minHeight: 480)
        .animation(.easeInOut(duration: 0.35), value: showOutput)
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

                if viewModel.isRunning {
                    StreamingIndicatorView()
                        .padding(.vertical, 6)
                } else {
                    Spacer()
                        .frame(height: 12)
                }

                OutputEditorView(
                    output: viewModel.outputPrompt,
                    onCopy: viewModel.copyOutputToClipboard
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        } else {
            VStack(spacing: 0) {
                Spacer()
                InputEditorView(
                    text: $viewModel.inputPrompt,
                    disabledReason: viewModel.improveDisabledReason,
                    showDisabledReason: true
                )
                .frame(maxHeight: 400)
                Spacer()
            }
        }
    }
}

#Preview {
    RootView(viewModel: PromptImproverViewModel())
}
