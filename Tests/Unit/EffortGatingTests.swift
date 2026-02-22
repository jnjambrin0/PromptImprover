import Foundation
import Testing
@testable import PromptImproverCore

struct EffortGatingTests {
    @Test
    func intersectsAllowlistWithBinarySupport() {
        var settings = EngineSettings.default
        settings[.codex] = ToolEngineSettings(
            defaultEngineModel: "gpt-5",
            defaultEffort: .high,
            customEngineModels: [],
            perModelEffortAllowlist: [
                "gpt-5": [.high, .medium]
            ]
        )

        let capabilities = ToolCapabilities(
            supportsModelFlag: true,
            supportsEffortConfig: true,
            supportedEffortValues: [.medium, .low]
        )

        let effective = settings.effectiveAllowedEfforts(for: .codex, model: "gpt-5", capabilities: capabilities)
        let resolvedDefault = settings.resolvedDefaultEffort(for: .codex, model: "gpt-5", capabilities: capabilities)

        #expect(effective == [.medium])
        #expect(resolvedDefault == nil)
    }

    @Test
    func claudeSonnetIsNotEffortEligibleByDefault() {
        let settings = EngineSettings.default
        let capabilities = ToolCapabilities(
            supportsModelFlag: true,
            supportsEffortConfig: true,
            supportedEffortValues: [.low, .medium, .high]
        )

        let effective = settings.effectiveAllowedEfforts(
            for: .claude,
            model: "claude-sonnet-4-6",
            capabilities: capabilities
        )

        #expect(effective.isEmpty)
    }

    @Test
    func claudeOpusIsEffortEligibleByDefault() {
        let settings = EngineSettings.default
        let capabilities = ToolCapabilities(
            supportsModelFlag: true,
            supportsEffortConfig: true,
            supportedEffortValues: [.low, .high]
        )

        let effective = settings.effectiveAllowedEfforts(
            for: .claude,
            model: "claude-opus-4-6",
            capabilities: capabilities
        )

        #expect(effective == [.low, .high])
    }

    @Test
    func dropsDefaultEffortWhenUnsupportedOrDisallowed() {
        var settings = EngineSettings.default
        settings[.claude] = ToolEngineSettings(
            defaultEngineModel: "claude-opus-4-6",
            defaultEffort: .medium,
            customEngineModels: [],
            perModelEffortAllowlist: [
                "claude-opus-4-6": [.high]
            ]
        )

        let unsupportedCapabilities = ToolCapabilities(
            supportsModelFlag: true,
            supportsEffortConfig: false,
            supportedEffortValues: []
        )
        let supportedButDisallowedCapabilities = ToolCapabilities(
            supportsModelFlag: true,
            supportsEffortConfig: true,
            supportedEffortValues: [.high]
        )

        let defaultWhenUnsupported = settings.resolvedDefaultEffort(
            for: .claude,
            model: "claude-opus-4-6",
            capabilities: unsupportedCapabilities
        )
        let defaultWhenDisallowed = settings.resolvedDefaultEffort(
            for: .claude,
            model: "claude-opus-4-6",
            capabilities: supportedButDisallowedCapabilities
        )

        #expect(defaultWhenUnsupported == nil)
        #expect(defaultWhenDisallowed == nil)
    }
}
