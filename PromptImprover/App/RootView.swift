import SwiftUI

struct RootView: View {
    @StateObject private var viewModel = PromptImproverViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controls
            PromptEditorView(text: $viewModel.inputPrompt)
            OutputView(
                output: viewModel.outputPrompt,
                isRunning: viewModel.isRunning,
                onCopy: viewModel.copyOutputToClipboard
            )
            statusArea
        }
        .padding(16)
        .frame(minWidth: 820, minHeight: 700)
        .onAppear {
            viewModel.refreshAvailability()
        }
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 16) {
            Picker("Tool", selection: $viewModel.selectedTool) {
                ForEach(Tool.allCases) { tool in
                    Text(tool.displayName).tag(tool)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 220)

            Picker("Target model", selection: $viewModel.selectedTargetModel) {
                ForEach(TargetModel.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 220)

            Spacer()

            if viewModel.isRunning {
                Button("Stop", action: viewModel.stop)
                    .keyboardShortcut(.cancelAction)
            }

            Button("Improve", action: viewModel.improve)
                .disabled(!viewModel.canImprove)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var statusArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Status: \(viewModel.statusMessage)")
                .font(.footnote)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if let disabledReason = viewModel.improveDisabledReason, !viewModel.isRunning {
                Text(disabledReason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    RootView()
}
