import Foundation
import Testing
@testable import PromptImproverCore

struct OutputContractTests {
    @Test
    func acceptsValidPayload() throws {
        let data = Data("{\"optimized_prompt\":\"Do this task clearly.\"}".utf8)
        let value = try OutputContract.normalizedOptimizedPrompt(from: data)
        #expect(value == "Do this task clearly.")
    }

    @Test
    func rejectsEmptyPrompt() {
        let data = Data("{\"optimized_prompt\":\"   \"}".utf8)
        #expect(throws: PromptImproverError.self) {
            _ = try OutputContract.normalizedOptimizedPrompt(from: data)
        }
    }

    @Test
    func rejectsCodeFences() {
        let data = Data("{\"optimized_prompt\":\"```json\"}".utf8)
        #expect(throws: PromptImproverError.self) {
            _ = try OutputContract.normalizedOptimizedPrompt(from: data)
        }
    }

    @Test
    func rejectsPrefixedOutput() {
        let data = Data("{\"optimized_prompt\":\"Here is the improved prompt: Do X\"}".utf8)
        #expect(throws: PromptImproverError.self) {
            _ = try OutputContract.normalizedOptimizedPrompt(from: data)
        }
    }

    @Test
    func rejectsAdditionalJSONKeys() {
        let data = Data("{\"optimized_prompt\":\"Do X\",\"extra\":\"not allowed\"}".utf8)
        #expect(throws: PromptImproverError.self) {
            _ = try OutputContract.normalizedOptimizedPrompt(from: data)
        }
    }
}
