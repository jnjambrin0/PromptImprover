import Foundation

struct CodexJSONLParser {
    private var lineBuffer = StreamLineBuffer()

    mutating func ingest(_ data: Data) throws -> [String] {
        let lines = try lineBuffer.append(data)
        return lines.flatMap(parseLine)
    }

    mutating func flush() throws -> [String] {
        guard let line = try lineBuffer.flushRemainder() else {
            return []
        }
        return parseLine(line)
    }

    private func parseLine(_ line: Data) -> [String] {
        guard
            let object = try? JSONSerialization.jsonObject(with: line),
            let dict = object as? [String: Any]
        else {
            return []
        }

        var deltas: [String] = []

        if let item = dict["item"] as? [String: Any],
           let type = item["type"] as? String,
           type == "agent_message",
           let text = item["text"] as? String {
            deltas.append(contentsOf: sanitize(text))
        }

        if let message = dict["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            for block in content where (block["type"] as? String) == "text" {
                if let text = block["text"] as? String {
                    deltas.append(contentsOf: sanitize(text))
                }
            }
        }

        return deltas
    }

    private func sanitize(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let dict = object as? [String: Any],
           let optimized = dict["optimized_prompt"] as? String {
            return [optimized]
        }

        return [trimmed]
    }
}
