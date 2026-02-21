import Foundation

protocol CLIProvider: AnyObject {
    func run(request: RunRequest, workspace: WorkspaceHandle) -> AsyncThrowingStream<RunEvent, Error>
    func cancel()
}

enum RunPromptBuilder {
    static func buildPrompt(for request: RunRequest) -> String {
        """
        Read INPUT_PROMPT.txt and TARGET_MODEL.txt in the current directory.
        Use CLAUDE_PROMPT_GUIDE.md for Claude 4.6 targets and GPT5.2_PROMPT_GUIDE.md for GPT-5.2 targets.
        For Gemini 3.0, use general prompt engineering best practices.

        Improve the prompt for the target model.

        Return ONLY valid JSON:
        {"optimized_prompt":"<english prompt>"}

        Hard constraints:
        - English output only.
        - No markdown fences.
        - No extra keys.
        - No preface or explanation.
        """
    }
}
