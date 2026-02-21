import Foundation

protocol CLIProvider: AnyObject {
    func run(request: RunRequest, workspace: WorkspaceHandle) -> AsyncThrowingStream<RunEvent, Error>
    func cancel()
}

enum RunPromptBuilder {
    static func buildPrompt(for request: RunRequest) -> String {
        """
        Read INPUT_PROMPT.txt, TARGET_MODEL.txt, and RUN_CONFIG.json in the current directory.
        In RUN_CONFIG.json, follow guideFilenamesInOrder exactly in listed order.
        Read and apply each guide file from guideFilenamesInOrder as ordered prompt-improvement guidance.
        If guideFilenamesInOrder is empty, use general prompt-engineering best practices.

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
