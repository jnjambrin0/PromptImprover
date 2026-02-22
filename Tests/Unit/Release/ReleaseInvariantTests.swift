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
        do {
            try ReleaseInvariantValidator.validateMonotonicBuildVersion(
                current: "2.0",
                published: ["2.0.0", "1.9.9"]
            )
            Issue.record("Expected non-monotonic build version violation")
        } catch {
            guard case ReleaseInvariantViolation.nonMonotonicBuildVersion = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test
    func invalidBuildVersionFormatFails() {
        do {
            _ = try ReleaseInvariantValidator.validateBundleVersion("1.0b")
            Issue.record("Expected invalid bundle version violation")
        } catch {
            guard case ReleaseInvariantViolation.invalidBundleVersion = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test
    func bundleIdentifierMismatchFails() {
        do {
            try ReleaseInvariantValidator.validateBundleIdentifier(
                expected: "com.jnjambrin0.PromptImprover",
                found: "com.example.Different"
            )
            Issue.record("Expected bundle identifier mismatch")
        } catch {
            guard case ReleaseInvariantViolation.bundleIdentifierMismatch = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test
    func appcastMappingMismatchFails() {
        do {
            try ReleaseInvariantValidator.validateAppcastMapping(
                expectedBuildVersion: "12",
                expectedShortVersion: "1.2.0",
                appcastBuildVersion: "11",
                appcastShortVersion: "1.2.0"
            )
            Issue.record("Expected appcast mapping mismatch")
        } catch {
            guard case ReleaseInvariantViolation.appcastVersionMismatch = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }
}
