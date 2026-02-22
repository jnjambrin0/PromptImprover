import Foundation
import Testing
@testable import PromptImproverCore

struct CodexJSONLParserTests {
    @Test
    func parsesAgentMessageText() throws {
        var parser = CodexJSONLParser()
        let data = try fixtureData(named: "codex_stream_sample", ext: "jsonl")

        let deltas = try parser.ingest(data)

        #expect(deltas.contains("partial output"))
        #expect(deltas.contains("Final optimized prompt"))
    }

    @Test
    func ignoresMalformedLines() throws {
        var parser = CodexJSONLParser()
        let data = Data("not-json\n".utf8)
        let deltas = try parser.ingest(data)
        #expect(deltas.isEmpty)
    }

    @Test
    func parsesLineSplitAcrossChunks() throws {
        var parser = CodexJSONLParser()
        let chunk1 = Data("{\"item\":{\"type\":\"agent_message\",\"text\":\"hello".utf8)
        let chunk2 = Data(" world\"}}\n".utf8)

        let first = try parser.ingest(chunk1)
        #expect(first.isEmpty)

        let second = try parser.ingest(chunk2)
        #expect(second == ["hello world"])
    }
}
