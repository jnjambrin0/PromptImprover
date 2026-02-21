import Foundation

struct CLIHealthCheck {
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

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--version"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CLIAvailability(
                tool: tool,
                executableURL: executableURL,
                installed: true,
                version: nil,
                healthMessage: "Failed to run \(tool.displayName): \(error.localizedDescription)"
            )
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let versionOutput = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if process.terminationStatus == 0 {
            return CLIAvailability(
                tool: tool,
                executableURL: executableURL,
                installed: true,
                version: versionOutput,
                healthMessage: nil
            )
        }

        return CLIAvailability(
            tool: tool,
            executableURL: executableURL,
            installed: true,
            version: nil,
            healthMessage: errorOutput?.isEmpty == false ? errorOutput : "Unable to run \(tool.displayName)."
        )
    }
}
