import Foundation
import Testing
@testable import PromptImproverCore

struct StreamLineBufferTests {
    @Test
    func parsesLinesAcrossChunks() throws {
        var buffer = StreamLineBuffer(maxLineBytes: 1024, maxBufferedBytes: 2048)

        let lines1 = try buffer.append(Data("first\nsec".utf8))
        #expect(lines1.count == 1)
        #expect(String(decoding: lines1[0], as: UTF8.self) == "first")

        let lines2 = try buffer.append(Data("ond\nthird\n".utf8))
        #expect(lines2.map { String(decoding: $0, as: UTF8.self) } == ["second", "third"])
    }

    @Test
    func lineTooLongThrows() {
        var buffer = StreamLineBuffer(maxLineBytes: 5, maxBufferedBytes: 100)

        #expect(throws: PromptImproverError.self) {
            _ = try buffer.append(Data("123456".utf8))
        }
    }

    @Test
    func bufferOverflowThrows() {
        var buffer = StreamLineBuffer(maxLineBytes: 100, maxBufferedBytes: 5)

        #expect(throws: PromptImproverError.self) {
            _ = try buffer.append(Data("123456".utf8))
        }
    }
}
