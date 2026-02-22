import Foundation

struct ClaudeStreamJSONParser {
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

        guard
            let type = dict["type"] as? String,
            type == "stream_event",
            let event = dict["event"] as? [String: Any],
            let eventType = event["type"] as? String,
            eventType == "content_block_delta",
            let delta = event["delta"] as? [String: Any],
            let deltaType = delta["type"] as? String
        else {
            return []
        }

        if deltaType == "text_delta", let text = delta["text"] as? String, !text.isEmpty {
            return [text]
        }

        if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String, !partial.isEmpty {
            return []
        }

        return []
    }
}
