import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: PromptImproverViewModel
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controls
            
            PromptEditorView(text: $viewModel.inputPrompt)
            
            if viewModel.isRunning || !viewModel.outputPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                OutputView(
                    output: viewModel.outputPrompt,
                    isRunning: viewModel.isRunning,
                    onCopy: viewModel.copyOutputToClipboard
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            statusArea
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 600)
        .background(
            Group {
                if reduceTransparency {
                    Color(NSColor.windowBackgroundColor)
                } else {
                    VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                }
            }
            .ignoresSafeArea()
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isRunning)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.outputPrompt)
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

            Picker("Target output model", selection: $viewModel.selectedTargetSlug) {
                ForEach(viewModel.outputModels) { model in
                    Text(model.displayName).tag(model.slug)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 220)
            .disabled(viewModel.outputModels.isEmpty)

            Spacer()

            if viewModel.isRunning {
                Button("Stop", action: viewModel.stop)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() }
                        else { NSCursor.pop() }
                    }
            }

            Button(action: viewModel.improve) {
                Label("Improve", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canImprove)
            .keyboardShortcut(.defaultAction)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() }
                else { NSCursor.pop() }
            }
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
    RootView(viewModel: PromptImproverViewModel())
}
