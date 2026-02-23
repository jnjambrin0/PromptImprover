import Foundation
import Testing
@testable import PromptImproverCore

struct ClaudeStreamJSONParserTests {
    @Test
    func parsesOnlyTextDeltasForUI() throws {
        var parser = ClaudeStreamJSONParser()
        let data = try fixtureData(named: "claude_stream_sample", ext: "ndjson")

        let deltas = try parser.ingest(data)

        #expect(deltas.contains("Hello "))
        #expect(deltas.contains("world"))
        #expect(!deltas.contains("{\"optimized_prompt\":\"abc\"}"))
    }

    @Test
    func ignoresUnsupportedEvents() throws {
        var parser = ClaudeStreamJSONParser()
        let data = Data("{\"type\":\"system\"}\n".utf8)
        let deltas = try parser.ingest(data)
        #expect(deltas.isEmpty)
    }

    @Test
    func parsesLineSplitAcrossChunks() throws {
        var parser = ClaudeStreamJSONParser()
        let chunk1 = Data("{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello".utf8)
        let chunk2 = Data(" there\"}}}\n".utf8)

        let first = try parser.ingest(chunk1)
        #expect(first.isEmpty)

        let second = try parser.ingest(chunk2)
        #expect(second == ["Hello there"])
    }
}
