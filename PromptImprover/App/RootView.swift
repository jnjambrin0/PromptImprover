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
        .frame(minWidth: 480, minHeight: 200)
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(.hidden, for: .windowToolbar)
        .background { WindowAccessor(showOutput: showOutput) }
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

// MARK: - Window Chrome & Sizing

private struct WindowAccessor: NSViewRepresentable {
    let showOutput: Bool

    private static let compactHeight: CGFloat = 250
    private static let expandedHeight: CGFloat = 500

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = AccessorView()
        let coordinator = context.coordinator
        let expanded = showOutput
        view.onWindowAvailable = { window in
            guard coordinator.window == nil else { return }
            coordinator.window = window
            coordinator.lastShowOutput = expanded
            Self.configureChrome(window)
            Self.resize(window, expanded: expanded, animate: false)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = context.coordinator.window,
              context.coordinator.lastShowOutput != showOutput else { return }
        context.coordinator.lastShowOutput = showOutput
        Self.resize(window, expanded: showOutput, animate: true)
    }

    final class Coordinator {
        var window: NSWindow?
        var lastShowOutput: Bool?
    }

    private final class AccessorView: NSView {
        var onWindowAvailable: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindowAvailable?(window) }
        }
    }

    private static func configureChrome(_ window: NSWindow) {
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
    }

    private static func resize(_ window: NSWindow, expanded: Bool, animate: Bool) {
        let targetHeight = expanded ? expandedHeight : compactHeight
        var frame = window.frame
        let delta = targetHeight - frame.height
        frame.size.height = targetHeight
        frame.origin.y -= delta // anchor top edge

        if animate {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }
}

#Preview {
    RootView(viewModel: PromptImproverViewModel())
}
