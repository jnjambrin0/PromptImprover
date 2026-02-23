import Foundation
import Testing
@testable import PromptImproverCore

struct ReleaseInvariantTests {
    @Test
    func monotonicBuildVersionPassesWhenCurrentIsGreater() throws {
        try ReleaseInvariantValidator.validateMonotonicBuildVersion(
            current: "2.1.0",
            published: ["1.9.5", "2.0", "1"]
        )
    }

    @Test
    func monotonicBuildVersionFailsWhenCurrentIsNotGreater() {
        #expect(throws: ReleaseInvariantViolation.self) {
            try ReleaseInvariantValidator.validateMonotonicBuildVersion(
                current: "2.0",
                published: ["2.0.0", "1.9.9"]
            )
        }
    }

    @Test
    func invalidBuildVersionFormatFails() {
        #expect(throws: ReleaseInvariantViolation.self) {
            _ = try ReleaseInvariantValidator.validateBundleVersion("1.0b")
        }
    }

    @Test
    func bundleIdentifierMismatchFails() {
        #expect(throws: ReleaseInvariantViolation.self) {
            try ReleaseInvariantValidator.validateBundleIdentifier(
                expected: "com.jnjambrin0.PromptImprover",
                found: "com.example.Different"
            )
        }
    }

    @Test
    func appcastMappingMismatchFails() {
        #expect(throws: ReleaseInvariantViolation.self) {
            try ReleaseInvariantValidator.validateAppcastMapping(
                expectedBuildVersion: "12",
                expectedShortVersion: "1.2.0",
                appcastBuildVersion: "11",
                appcastShortVersion: "1.2.0"
            )
        }
    }
}
