import Foundation

struct CLIHealthCheck {
    private let localCommandRunner: LocalCommandRunning
    private let commandTimeout: TimeInterval

    init(
        localCommandRunner: LocalCommandRunning = LocalCommandRunner(),
        commandTimeout: TimeInterval = 5
    ) {
        self.localCommandRunner = localCommandRunner
        self.commandTimeout = commandTimeout
    }

    func check(tool: Tool, executableURL: URL?) -> CLIAvailability {
        guard let executableURL else {
            return CLIAvailability(
                tool: tool,
                executableURL: nil,
                installed: false,
                version: nil,
                healthMessage: tool.missingInstallMessage
            )
        }

        let result = localCommandRunner.run(
            executableURL: executableURL,
            arguments: ["--version"],
            environment: CLIExecutionEnvironment.environmentForExecutable(
                executableURL: executableURL,
                baseEnv: ProcessInfo.processInfo.environment
            ),
            timeout: commandTimeout
        )

        if let launchErrorDescription = result.launchErrorDescription {
            return CLIAvailability(
                tool: tool,
                executableURL: executableURL,
                installed: true,
                version: nil,
                healthMessage: "Failed to run \(tool.displayName): \(launchErrorDescription)"
            )
        }

        if result.timedOut {
            return CLIAvailability(
                tool: tool,
                executableURL: executableURL,
                installed: true,
                version: nil,
                healthMessage: "\(tool.displayName) version check timed out."
            )
        }

        let versionOutput = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let errorOutput = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        if result.status == 0 {
            return CLIAvailability(
                tool: tool,
                executableURL: executableURL,
                installed: true,
                version: versionOutput.isEmpty ? nil : versionOutput,
                healthMessage: nil
            )
        }

        let failureMessage: String
        if !errorOutput.isEmpty {
            failureMessage = errorOutput
        } else if !versionOutput.isEmpty {
            failureMessage = versionOutput
        } else {
            failureMessage = "Unable to run \(tool.displayName)."
        }

        return CLIAvailability(
            tool: tool,
            executableURL: executableURL,
            installed: true,
            version: nil,
            healthMessage: failureMessage
        )
    }
}
