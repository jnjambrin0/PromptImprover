import Foundation
import Testing
@testable import PromptImproverCore

@Suite(.serialized)
struct CLIEnvironmentIntegrationTests {
    @Test
    func healthCheckSupportsEnvWrappedExecutableInSameDirectory() throws {
        let scripts = try makeEnvWrappedExecutableDirectory(versionOutput: "codex-cli 9.9.9")
        let availability = CLIHealthCheck().check(tool: .codex, executableURL: scripts.executableURL)

        #expect(availability.installed)
        #expect(availability.version == "codex-cli 9.9.9")
        #expect(availability.healthMessage == nil)
    }

    @Test
    func capabilityDetectorSupportsEnvWrappedExecutableInSameDirectory() throws {
        let scripts = try makeEnvWrappedExecutableDirectory(versionOutput: "codex-cli 0.200.0")
        let detector = ToolCapabilityDetector()
        let signature = try #require(
            detector.makeSignature(
                tool: .codex,
                executableURL: scripts.executableURL,
                versionString: "codex-cli 0.200.0"
            )
        )

        let capabilities = detector.detectCapabilities(
            tool: .codex,
            executableURL: scripts.executableURL,
            signature: signature
        )

        #expect(capabilities.supportsModelFlag)
        #expect(capabilities.supportsEffortConfig)
        #expect(capabilities.supportedEffortValues == [.low, .medium, .high, .xhigh])
    }

    @Test
    func claudeCapabilityDetectorIgnoresXhighEvenIfBinaryMentionsIt() throws {
        let scripts = try makeClaudeEnvWrappedExecutableDirectory(versionOutput: "claude-code 1.2.3")
        let detector = ToolCapabilityDetector()
        let signature = try #require(
            detector.makeSignature(
                tool: .claude,
                executableURL: scripts.executableURL,
                versionString: "claude-code 1.2.3"
            )
        )

        let capabilities = detector.detectCapabilities(
            tool: .claude,
            executableURL: scripts.executableURL,
            signature: signature
        )

        #expect(capabilities.supportsModelFlag)
        #expect(capabilities.supportsEffortConfig)
        #expect(capabilities.supportedEffortValues == [.low, .medium, .high])
    }

    private func makeEnvWrappedExecutableDirectory(versionOutput: String) throws -> (directoryURL: URL, executableURL: URL) {
        let directoryURL = makeTemporaryDirectory()
        let runtimeName = "prompt_improver_fake_runtime"
        let runtimeURL = directoryURL.appendingPathComponent(runtimeName)
        let executableURL = directoryURL.appendingPathComponent("codex")

        let runtimeScript = """
#!/bin/sh
shift
if [ "$1" = "--version" ]; then
  echo "\(versionOutput)"
  exit 0
fi
if [ "$1" = "exec" ] && [ "$2" = "--help" ]; then
  cat <<'EOF'
Usage: codex exec [OPTIONS]
  --model <MODEL>
  -c model_reasoning_effort=<low|medium|high|xhigh>
EOF
  exit 0
fi
echo "unsupported args: $*" 1>&2
exit 1
"""
        try writeExecutableScript(at: runtimeURL, contents: runtimeScript)

        let wrapperScript = "#!/usr/bin/env \(runtimeName)\n"
        try writeExecutableScript(at: executableURL, contents: wrapperScript)

        return (directoryURL, executableURL)
    }

    private func makeClaudeEnvWrappedExecutableDirectory(versionOutput: String) throws -> (directoryURL: URL, executableURL: URL) {
        let directoryURL = makeTemporaryDirectory()
        let runtimeName = "prompt_improver_fake_claude_runtime"
        let runtimeURL = directoryURL.appendingPathComponent(runtimeName)
        let executableURL = directoryURL.appendingPathComponent("claude")

        let runtimeScript = """
#!/bin/sh
shift
if [ "$1" = "--version" ]; then
  echo "\(versionOutput)"
  exit 0
fi
if [ "$1" = "--help" ]; then
  cat <<'EOF'
Usage: claude [OPTIONS]
  --model <MODEL>
  --effort <low|medium|high|xhigh>
EOF
  exit 0
fi
echo "unsupported args: $*" 1>&2
exit 1
"""
        try writeExecutableScript(at: runtimeURL, contents: runtimeScript)

        let wrapperScript = "#!/usr/bin/env \(runtimeName)\n"
        try writeExecutableScript(at: executableURL, contents: wrapperScript)

        return (directoryURL, executableURL)
    }

    private func makeTemporaryDirectory() -> URL {
        (try? TestSupport.makeTemporaryDirectory(prefix: "CLIEnvironment"))
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    private func writeExecutableScript(at url: URL, contents: String) throws {
        try TestSupport.writeExecutableScript(at: url, script: contents)
    }
}
