import Foundation

struct CLIDiscovery {
    private let fileManager: FileManager
    private let homeDirectoryPath: String
    private let localCommandRunner: LocalCommandRunning
    private let baseCandidatesByTool: [Tool: [String]]?

    init(
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory(),
        localCommandRunner: LocalCommandRunning = LocalCommandRunner(),
        baseCandidatesByTool: [Tool: [String]]? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectoryPath = homeDirectoryPath
        self.localCommandRunner = localCommandRunner
        self.baseCandidatesByTool = baseCandidatesByTool
    }

    func resolve(tool: Tool) -> URL? {
        if let shellPath = resolveViaShell(tool: tool) {
            return shellPath
        }
        return commonPaths(for: tool).first(where: { fileManager.isExecutableFile(atPath: $0.path) })
    }

    private func resolveViaShell(tool: Tool) -> URL? {
        let result = localCommandRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "command -v \(tool.rawValue)"],
            environment: ProcessInfo.processInfo.environment,
            timeout: 3
        )

        if result.timedOut || result.status != 0 {
            return nil
        }

        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func commonPaths(for tool: Tool) -> [URL] {
        var candidates = baseCandidatesByTool?[tool] ?? defaultCandidates(for: tool)
        candidates.append(contentsOf: nvmVersionedCandidates(tool: tool))

        var seen: Set<String> = []
        let uniqueCandidates = candidates.filter { seen.insert($0).inserted }
        return uniqueCandidates.map { URL(fileURLWithPath: $0) }
    }

    private func defaultCandidates(for tool: Tool) -> [String] {
        switch tool {
        case .codex:
            return [
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
                homeDirectoryPath + "/.nvm/versions/node/current/bin/codex"
            ]
        case .claude:
            return [
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
                homeDirectoryPath + "/.local/bin/claude"
            ]
        }
    }

    private func nvmVersionedCandidates(tool: Tool) -> [String] {
        let nodeVersionsRoot = URL(fileURLWithPath: homeDirectoryPath, isDirectory: true)
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
