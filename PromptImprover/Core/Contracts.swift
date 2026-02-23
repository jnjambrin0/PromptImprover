import Foundation

struct OptimizedPromptPayload: Codable {
    let optimized_prompt: String
}

enum OutputContract {
    static func normalizedOptimizedPrompt(from data: Data) throws -> String {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PromptImproverError.schemaMismatch
        }
        return try normalizedOptimizedPrompt(from: object)
    }

    static func normalizedOptimizedPrompt(from jsonObject: Any) throws -> String {
        guard
            let dict = jsonObject as? [String: Any],
            dict.count == 1,
            let prompt = dict["optimized_prompt"] as? String
        else {
            throw PromptImproverError.schemaMismatch
        }
        return try normalizePrompt(prompt)
    }

    static func normalizePrompt(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw PromptImproverError.invalidOutput("Optimized prompt is empty.")
        }

        if normalized.contains("```") {
            throw PromptImproverError.invalidOutput("Output contains fenced code blocks.")
        }

        let lowered = normalized.lowercased()
        let disallowedPrefixes = [
            "here's the improved prompt",
            "here’s the improved prompt",
            "here is the improved prompt",
            "improved prompt:",
            "optimized prompt:",
            "here's your optimized prompt",
            "here’s your optimized prompt",
            "here is your optimized prompt"
        ]

        if disallowedPrefixes.contains(where: { lowered.hasPrefix($0) }) {
            throw PromptImproverError.invalidOutput("Output contains explanatory prefix text.")
        }

        return normalized
    }
}
