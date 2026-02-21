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
        do {
            _ = try OutputContract.normalizedOptimizedPrompt(from: data)
            Issue.record("Expected invalid output error")
        } catch {
            // expected
        }
    }

    @Test
    func rejectsCodeFences() {
        let data = Data("{\"optimized_prompt\":\"```json\"}".utf8)
        do {
            _ = try OutputContract.normalizedOptimizedPrompt(from: data)
            Issue.record("Expected invalid output error")
        } catch {
            // expected
        }
    }

    @Test
    func rejectsPrefixedOutput() {
        let data = Data("{\"optimized_prompt\":\"Here is the improved prompt: Do X\"}".utf8)
        do {
            _ = try OutputContract.normalizedOptimizedPrompt(from: data)
            Issue.record("Expected invalid output error")
        } catch {
            // expected
        }
    }

    @Test
    func rejectsAdditionalJSONKeys() {
        let data = Data("{\"optimized_prompt\":\"Do X\",\"extra\":\"not allowed\"}".utf8)
        do {
            _ = try OutputContract.normalizedOptimizedPrompt(from: data)
            Issue.record("Expected schema mismatch")
        } catch {
            guard case PromptImproverError.schemaMismatch = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }
}
