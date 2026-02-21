import Foundation
import Testing
@testable import PromptImproverCore

struct ProviderBehaviorTests {
    @Test
    func codexRetriesWithInheritedHomeWhenIsolatedAuthFails() async throws {
        let executableURL = try makeExecutableScript(
            name: "fake-codex-auth-fallback",
            script: """
            #!/bin/zsh
            set -e
            out=""
            while [[ $# -gt 0 ]]; do
              if [[ "$1" == "--output-last-message" ]]; then
                out="$2"
                shift 2
                continue
              fi
              shift
            done
            if [[ -n "${CODEX_HOME:-}" ]]; then
              echo '{"type":"error","message":"401 Unauthorized: Missing bearer"}'
              echo '{"type":"turn.failed","error":{"message":"401 Unauthorized: Missing bearer"}}'
              exit 1
            fi
            echo '{"type":"item.completed","item":{"type":"agent_message","text":"partial from inherited"}}'
            printf '{"optimized_prompt":"Prompt from inherited home"}' > "$out"
            """
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }

        let request = RunRequest(tool: .codex, targetModel: .gpt52, inputPrompt: "Improve this.")
        let workspace = try makeWorkspace(request: request)
        defer { workspace.cleanup() }

        let provider = CodexProvider(executableURL: executableURL)
        let final = try await collectCompletedPrompt(from: provider.run(request: request, workspace: workspace))
        #expect(final == "Prompt from inherited home")
    }

    @Test
    func codexReturnsNotAuthenticatedWhenBothAttemptsFail() async throws {
        let executableURL = try makeExecutableScript(
            name: "fake-codex-auth-fail",
            script: """
            #!/bin/zsh
            echo '{"type":"error","message":"401 Unauthorized: Missing bearer"}'
            echo '{"type":"turn.failed","error":{"message":"401 Unauthorized: Missing bearer"}}'
            exit 1
            """
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }

        let request = RunRequest(tool: .codex, targetModel: .gpt52, inputPrompt: "Improve this.")
        let workspace = try makeWorkspace(request: request)
        defer { workspace.cleanup() }

        let provider = CodexProvider(executableURL: executableURL)

        do {
            _ = try await collectCompletedPrompt(from: provider.run(request: request, workspace: workspace))
            Issue.record("Expected toolNotAuthenticated error")
        } catch {
            guard case PromptImproverError.toolNotAuthenticated = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test
    func codexReturnsExecutionFailedForNonAuthError() async throws {
        let executableURL = try makeExecutableScript(
            name: "fake-codex-non-auth-fail",
            script: """
            #!/bin/zsh
            echo '{"type":"error","message":"permission denied while running codex"}'
            exit 1
            """
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }

        let request = RunRequest(tool: .codex, targetModel: .gpt52, inputPrompt: "Improve this.")
        let workspace = try makeWorkspace(request: request)
        defer { workspace.cleanup() }

        let provider = CodexProvider(executableURL: executableURL)

        do {
            _ = try await collectCompletedPrompt(from: provider.run(request: request, workspace: workspace))
            Issue.record("Expected toolExecutionFailed error")
        } catch {
            guard case PromptImproverError.toolExecutionFailed = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test
    func codexPrependsExecutableDirectoryToPath() async throws {
        let executableURL = try makeExecutableScript(
            name: "fake-codex-path-check",
            script: """
            #!/bin/zsh
            set -e
            out=""
            while [[ $# -gt 0 ]]; do
              if [[ "$1" == "--output-last-message" ]]; then
                out="$2"
                shift 2
                continue
              fi
              shift
            done

            script_dir="$(cd "$(dirname "$0")" && pwd)"
            case ":${PATH}:" in
              *":$script_dir:"*) ;;
              *)
                echo '{"type":"error","message":"PATH does not include codex executable directory"}'
                exit 1
                ;;
            esac

            printf '{"optimized_prompt":"Prompt with patched PATH"}' > "$out"
            """
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }

        let request = RunRequest(tool: .codex, targetModel: .gpt52, inputPrompt: "Improve this.")
        let workspace = try makeWorkspace(request: request)
        defer { workspace.cleanup() }

        let provider = CodexProvider(executableURL: executableURL)
        let final = try await collectCompletedPrompt(from: provider.run(request: request, workspace: workspace))
        #expect(final == "Prompt with patched PATH")
    }

    @Test
    func codexDoesNotEmitIntermediateDeltas() async throws {
        let executableURL = try makeExecutableScript(
            name: "fake-codex-no-deltas",
            script: """
            #!/bin/zsh
            set -e
            out=""
            while [[ $# -gt 0 ]]; do
              if [[ "$1" == "--output-last-message" ]]; then
                out="$2"
                shift 2
                continue
              fi
              shift
            done
            echo '{"type":"item.completed","item":{"type":"agent_message","text":"thinking output"}}'
            printf '{"optimized_prompt":"Final prompt only"}' > "$out"
            """
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }

        let request = RunRequest(tool: .codex, targetModel: .gpt52, inputPrompt: "Improve this.")
        let workspace = try makeWorkspace(request: request)
        defer { workspace.cleanup() }

        let provider = CodexProvider(executableURL: executableURL)
        let events = try await collectEvents(from: provider.run(request: request, workspace: workspace))

        var deltaCount = 0
        var completedPrompt: String?
        for event in events {
            switch event {
            case .delta:
                deltaCount += 1
            case .completed(let prompt):
                completedPrompt = prompt
            case .failed, .cancelled:
                break
            }
        }

        #expect(deltaCount == 0)
        #expect(completedPrompt == "Final prompt only")
    }

    @Test
    func codexPassesConfiguredModelAndEffort() async throws {
        let executableURL = try makeExecutableScript(
            name: "fake-codex-model-effort",
            script: """
            #!/bin/zsh
            set -e
            out=""
            model=""
            effort=""
            while [[ $# -gt 0 ]]; do
              case "$1" in
                --output-last-message)
                  out="$2"
                  shift 2
                  ;;
                --model)
                  model="$2"
                  shift 2
                  ;;
                -c)
                  if [[ "$2" == model_reasoning_effort=* ]]; then
                    effort="${2#model_reasoning_effort=}"
                  fi
                  shift 2
                  ;;
                *)
                  shift
                  ;;
              esac
            done

            if [[ "$model" != "gpt-5-mini" ]]; then
              echo '{"type":"error","message":"missing codex model argument"}'
              exit 1
            fi

            if [[ "$effort" != "high" ]]; then
              echo '{"type":"error","message":"missing codex effort argument"}'
              exit 1
            fi

            printf '{"optimized_prompt":"Prompt with model and effort"}' > "$out"
            """
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }

        let request = RunRequest(
            tool: .codex,
            targetModel: .gpt52,
            inputPrompt: "Improve this.",
            engineModel: "gpt-5-mini",
            engineEffort: .high
        )
        let workspace = try makeWorkspace(request: request)
        defer { workspace.cleanup() }

        let provider = CodexProvider(executableURL: executableURL)
        let final = try await collectCompletedPrompt(from: provider.run(request: request, workspace: workspace))
        #expect(final == "Prompt with model and effort")
    }

    @Test
    func codexPassesModelWithoutEffortWhenEffortMissing() async throws {
        let executableURL = try makeExecutableScript(
            name: "fake-codex-model-only",
            script: """
            #!/bin/zsh
            set -e
            out=""
            model=""
            effort=""
            while [[ $# -gt 0 ]]; do
              case "$1" in
                --output-last-message)
                  out="$2"
                  shift 2
                  ;;
                --model)
                  model="$2"
                  shift 2
                  ;;
                -c)
                  if [[ "$2" == model_reasoning_effort=* ]]; then
                    effort="${2#model_reasoning_effort=}"
                  fi
                  shift 2
                  ;;
                *)
                  shift
                  ;;
              esac
            done

            if [[ "$model" != "gpt-5" ]]; then
              echo '{"type":"error","message":"missing codex model argument"}'
              exit 1
            fi

            if [[ -n "$effort" ]]; then
              echo '{"type":"error","message":"unexpected codex effort argument"}'
              exit 1
            fi

            printf '{"optimized_prompt":"Prompt with model only"}' > "$out"
            """
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }

        let request = RunRequest(
            tool: .codex,
            targetModel: .gpt52,
            inputPrompt: "Improve this.",
            engineModel: "gpt-5",
            engineEffort: nil
        )
        let workspace = try makeWorkspace(request: request)
        defer { workspace.cleanup() }

        let provider = CodexProvider(executableURL: executableURL)
        let final = try await collectCompletedPrompt(from: provider.run(request: request, workspace: workspace))
        #expect(final == "Prompt with model only")
    }

    @Test
    func claudeIgnoresToolUseInputAndExtractsResultPayload() async throws {
        let executableURL = try makeExecutableScript(
            name: "fake-claude-stream-result",
            script: """
            #!/bin/zsh
            mode=""
            while [[ $# -gt 0 ]]; do
              if [[ "$1" == "--output-format" ]]; then
                mode="$2"
                shift 2
                continue
              fi
              shift
            done
            if [[ "$mode" == "stream-json" ]]; then
              cat <<'JSON'
            {"type":"assistant","message":{"content":[{"type":"tool_use","input":{"file_path":"/tmp/input.txt"}}]}}
            {"type":"result","result":"{\\"optimized_prompt\\":\\"Prompt from stream result\\"}"}
            JSON
              exit 0
            fi
            if [[ "$mode" == "json" ]]; then
              echo '{"type":"result","structured_output":{"optimized_prompt":"Prompt from fallback json"}}'
              exit 0
            fi
            echo "unexpected mode" >&2
            exit 2
            """
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }

        let request = RunRequest(tool: .claude, targetModel: .claude46, inputPrompt: "Improve this.")
        let workspace = try makeWorkspace(request: request)
        defer { workspace.cleanup() }

        let provider = ClaudeProvider(executableURL: executableURL)
        let final = try await collectCompletedPrompt(from: provider.run(request: request, workspace: workspace))
        #expect(final == "Prompt from stream result")
    }

    @Test
    func claudeFallsBackToStructuredOutputWhenStreamHasNoResult() async throws {
        let executableURL = try makeExecutableScript(
            name: "fake-claude-fallback",
            script: """
            #!/bin/zsh
            mode=""
            while [[ $# -gt 0 ]]; do
              if [[ "$1" == "--output-format" ]]; then
                mode="$2"
                shift 2
                continue
              fi
              shift
            done
            if [[ "$mode" == "stream-json" ]]; then
              cat <<'JSON'
            {"type":"assistant","message":{"content":[{"type":"tool_use","input":{"file_path":"/tmp/input.txt"}}]}}
            {"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"partial"}}}
            JSON
              exit 0
            fi
            if [[ "$mode" == "json" ]]; then
              echo '{"type":"result","structured_output":{"optimized_prompt":"Prompt from fallback json"}}'
              exit 0
            fi
            echo "unexpected mode" >&2
            exit 2
            """
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }

        let request = RunRequest(tool: .claude, targetModel: .claude46, inputPrompt: "Improve this.")
        let workspace = try makeWorkspace(request: request)
        defer { workspace.cleanup() }

        let provider = ClaudeProvider(executableURL: executableURL)
        let final = try await collectCompletedPrompt(from: provider.run(request: request, workspace: workspace))
        #expect(final == "Prompt from fallback json")
    }

    @Test
    func claudePassesModelToStreamAndFallbackInvocations() async throws {
        let executableURL = try makeExecutableScript(
            name: "fake-claude-model-all-modes",
            script: """
            #!/bin/zsh
            mode=""
            model=""
            while [[ $# -gt 0 ]]; do
              if [[ "$1" == "--output-format" ]]; then
                mode="$2"
                shift 2
                continue
              fi
              if [[ "$1" == "--model" ]]; then
                model="$2"
                shift 2
                continue
              fi
              shift
            done

            if [[ "$model" != "claude-opus-4-6" ]]; then
              echo "missing model" >&2
              exit 1
            fi

            if [[ "$mode" == "stream-json" ]]; then
              cat <<'JSON'
            {"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"partial"}}}
            JSON
              exit 0
            fi

            if [[ "$mode" == "json" ]]; then
              echo '{"type":"result","structured_output":{"optimized_prompt":"Prompt from modeled fallback"}}'
              exit 0
            fi

            echo "unexpected mode" >&2
            exit 2
            """
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }

        let request = RunRequest(
            tool: .claude,
            targetModel: .claude46,
            inputPrompt: "Improve this.",
            engineModel: "claude-opus-4-6",
            engineEffort: nil
        )
        let workspace = try makeWorkspace(request: request)
        defer { workspace.cleanup() }

        let provider = ClaudeProvider(executableURL: executableURL)
        let final = try await collectCompletedPrompt(from: provider.run(request: request, workspace: workspace))
        #expect(final == "Prompt from modeled fallback")
    }

    @Test
    func claudeProviderReadsWorkspaceEffortConfiguration() async throws {
        let executableURL = try makeExecutableScript(
            name: "fake-claude-workspace-effort",
            script: """
            #!/bin/zsh
            mode=""
            while [[ $# -gt 0 ]]; do
              if [[ "$1" == "--output-format" ]]; then
                mode="$2"
                shift 2
                continue
              fi
              shift
            done

            if [[ ! -f ".claude/settings.json" ]]; then
              echo "missing .claude/settings.json" >&2
              exit 1
            fi

            if ! grep -Eq '"effortLevel"[[:space:]]*:[[:space:]]*"high"' ".claude/settings.json"; then
              echo "missing effortLevel in project settings" >&2
              cat ".claude/settings.json" >&2
              exit 1
            fi

            if [[ "$mode" == "stream-json" ]]; then
              echo '{"type":"result","result":"{\\"optimized_prompt\\":\\"Prompt from effort-configured workspace\\"}"}'
              exit 0
            fi

            echo '{"type":"result","structured_output":{"optimized_prompt":"Prompt from effort-configured workspace"}}'
            """
        )
        defer { try? FileManager.default.removeItem(at: executableURL) }

        let request = RunRequest(
            tool: .claude,
            targetModel: .claude46,
            inputPrompt: "Improve this.",
            engineModel: "claude-opus-4-6",
            engineEffort: .high
        )
        let workspace = try makeWorkspace(request: request)
        defer { workspace.cleanup() }

        let provider = ClaudeProvider(executableURL: executableURL)
        let final = try await collectCompletedPrompt(from: provider.run(request: request, workspace: workspace))
        #expect(final == "Prompt from effort-configured workspace")
    }

    private func makeWorkspace(request: RunRequest) throws -> WorkspaceHandle {
        let templates = Templates(bundle: .main, fallbackRoot: templateRootURL())
        let manager = WorkspaceManager(templates: templates)
        return try manager.createRunWorkspace(request: request)
    }

    private func collectCompletedPrompt(from stream: AsyncThrowingStream<RunEvent, Error>) async throws -> String? {
        var prompt: String?
        for try await event in stream {
            if case .completed(let value) = event {
                prompt = value
            }
        }
        return prompt
    }

    private func collectEvents(from stream: AsyncThrowingStream<RunEvent, Error>) async throws -> [RunEvent] {
        var events: [RunEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func makeExecutableScript(name: String, script: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PromptImproverProviderTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("\(name)-\(UUID().uuidString).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
