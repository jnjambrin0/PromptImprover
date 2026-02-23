import Foundation

protocol CLIProvider: AnyObject {
    func run(request: RunRequest, workspace: WorkspaceHandle) -> AsyncThrowingStream<RunEvent, Error>
    func cancel()
}

enum RunPromptBuilder {
    static func buildPrompt(for request: RunRequest, guideFilenamesInOrder: [String]) -> String {
        let guideInstructions: String
        if guideFilenamesInOrder.isEmpty {
            guideInstructions = "No guide files are provided; use general prompt-engineering best practices."
        } else {
            let orderedGuideList = guideFilenamesInOrder.map { "- \($0)" }.joined(separator: "\n")
            guideInstructions = """
            Read and apply these guide files in exact order:
            \(orderedGuideList)
            """
        }

        return """
        Read INPUT_PROMPT.txt in the current directory.
        Target output model: \(request.targetDisplayName) (slug: \(request.targetSlug)).
        \(guideInstructions)

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
