import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: PromptImproverViewModel
    @ObservedObject var updateManager: SparkleUpdateManager

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
        .alert(
            "Move PromptImprover to Applications?",
            isPresented: $updateManager.isMovePromptPresented
        ) {
            Button("Move and Relaunch") {
                updateManager.moveToApplicationsAndRelaunch()
            }
            Button("Not Now", role: .cancel) {
                updateManager.deferMovePrompt()
            }
        } message: {
            Text(movePromptBodyText)
        }
        .task {
            updateManager.evaluateInstallLocationOnLaunch()
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

    private var movePromptBodyText: String {
        switch updateManager.installState {
        case let .notInApplications(readOnly, translocated):
            var details: [String] = [
                "To keep automatic updates reliable, run PromptImprover from /Applications or ~/Applications."
            ]
            if readOnly {
                details.append("Current volume is read-only.")
            }
            if translocated {
                details.append("Current launch appears translocated.")
            }
            return details.joined(separator: " ")
        default:
            return "To keep automatic updates reliable, run PromptImprover from /Applications or ~/Applications."
        }
    }
}

#Preview {
    RootView(
        viewModel: PromptImproverViewModel(),
        updateManager: SparkleUpdateManager(
            updater: PreviewSparkleUpdaterController(),
            installLocationManager: PreviewInstallLocationManager()
        )
    )
}

@MainActor
private final class PreviewSparkleUpdaterController: SparkleUpdaterControlling {
    var hasStartedUpdater: Bool = true
    var canCheckForUpdates: Bool = true
    var automaticallyChecksForUpdates: Bool = true
    var automaticallyDownloadsUpdates: Bool = false
    var allowsAutomaticUpdates: Bool = true

    func startUpdater() {}
    func checkForUpdates() {}
    func observeStateChanges(_ handler: @escaping @MainActor () -> Void) -> AnyObject {
        _ = handler
        return NSObject()
    }
}

@MainActor
private struct PreviewInstallLocationManager: InstallLocationManaging {
    func evaluateInstallState() -> InstallState {
        .updatable
    }

    func moveAndRelaunchIfNeeded() async throws -> URL {
        URL(fileURLWithPath: "/Applications/PromptImprover.app")
    }
}
