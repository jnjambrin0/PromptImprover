import Foundation

struct CLIDiscovery {
    func resolve(tool: Tool) -> URL? {
        if let shellPath = resolveViaShell(tool: tool) {
            return shellPath
        }
        return commonPaths(for: tool).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    private func resolveViaShell(tool: Tool) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(tool.rawValue)"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard var path = String(data: data, encoding: .utf8) else {
            return nil
        }
        path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func commonPaths(for tool: Tool) -> [URL] {
        var candidates: [String]
        switch tool {
        case .codex:
            candidates = [
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
                NSHomeDirectory() + "/.nvm/versions/node/current/bin/codex"
            ]
            candidates.append(contentsOf: nvmVersionedCandidates(tool: tool))
        case .claude:
            candidates = [
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
                NSHomeDirectory() + "/.local/bin/claude"
            ]
        }

        var seen: Set<String> = []
        let uniqueCandidates = candidates.filter { seen.insert($0).inserted }
        return uniqueCandidates.map { URL(fileURLWithPath: $0) }
    }

    private func nvmVersionedCandidates(tool: Tool) -> [String] {
        let fileManager = FileManager.default
        let nodeVersionsRoot = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".nvm/versions/node", isDirectory: true)

        guard let entries = try? fileManager.contentsOfDirectory(
            at: nodeVersionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let versionDirectories = entries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && url.lastPathComponent.hasPrefix("v")
        }

        let sortedVersions = versionDirectories.sorted {
            $0.lastPathComponent.compare(
                $1.lastPathComponent,
                options: [.numeric, .caseInsensitive]
            ) == .orderedDescending
        }

        return sortedVersions.map { $0.appendingPathComponent("bin/\(tool.rawValue)").path }
    }
}
