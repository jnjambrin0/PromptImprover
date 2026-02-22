import SwiftUI

struct UpdatesSettingsView: View {
    @ObservedObject var updateManager: SparkleUpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Software Updates")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Automatically check for updates", isOn: $updateManager.automaticallyChecksForUpdates)

                Toggle("Automatically download and install updates", isOn: $updateManager.automaticallyDownloadsUpdates)
                    .disabled(!updateManager.allowsAutomaticUpdates)

                HStack(spacing: 12) {
                    Button("Check for Updates…") {
                        updateManager.checkForUpdates()
                    }
                    .disabled(!updateManager.canCheckForUpdates)

                    Text(versionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))
            )

            if let updaterConfigurationMessage = updateManager.updaterConfigurationMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Updater Configuration")
                        .font(.headline)
                    Text(updaterConfigurationMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red.opacity(0.45), lineWidth: 1)
                )
            }

            if let warning = updateManager.installWarningMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Install Location")
                        .font(.headline)
                    Text(warning)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if case .notInApplications = updateManager.installState {
                        Button("Move and Relaunch") {
                            updateManager.moveToApplicationsAndRelaunch()
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var versionSummary: String {
        let shortVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "-"
        let buildVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "-"
        return "Version \(shortVersion) (\(buildVersion))"
    }
}

#Preview {
    UpdatesSettingsView(
        updateManager: SparkleUpdateManager(
            updater: UpdatesPreviewSparkleUpdaterController(),
            installLocationManager: UpdatesPreviewInstallLocationManager()
        )
    )
    .frame(width: 720, height: 520)
}

@MainActor
private final class UpdatesPreviewSparkleUpdaterController: SparkleUpdaterControlling {
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
private struct UpdatesPreviewInstallLocationManager: InstallLocationManaging {
    func evaluateInstallState() -> InstallState {
        .notInApplications(readOnly: false, translocated: false)
    }

    func moveAndRelaunchIfNeeded() async throws -> URL {
        URL(fileURLWithPath: "/Applications/PromptImprover.app")
    }
}
