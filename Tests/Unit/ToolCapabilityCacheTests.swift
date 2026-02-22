import Foundation
import Testing
@testable import PromptImproverCore

struct ToolCapabilityCacheTests {
    @Test
    func defaultCacheFileURLUsesCachesDirectory() {
        let layout = AppStorageLayout.bestEffort()
        let fileURL = ToolCapabilityCacheStore.defaultFileURL()

        #expect(fileURL.path.hasPrefix(layout.cachesRoot.path))
        #expect(fileURL.lastPathComponent == "cli-discovery-cache.json")
    }

    @Test
    func reusesPersistedCacheAcrossStoreInstances() {
        let fileURL = makeCacheFileURL()
        let executableURL = URL(fileURLWithPath: "/tmp/fake-codex")

        let firstDetector = FakeCapabilityDetector()
        let firstStore = ToolCapabilityCacheStore(fileURL: fileURL, detector: firstDetector)
        let first = firstStore.capabilities(
            for: .codex,
            executableURL: executableURL,
            versionString: "codex-cli 0.104.0"
        )

        let secondDetector = FakeCapabilityDetector()
        secondDetector.capabilitiesToReturn = ToolCapabilities(
            supportsModelFlag: true,
            supportsEffortConfig: false,
            supportedEffortValues: []
        )
        let secondStore = ToolCapabilityCacheStore(fileURL: fileURL, detector: secondDetector)
        let second = secondStore.capabilities(
            for: .codex,
            executableURL: executableURL,
            versionString: "codex-cli 0.104.0"
        )

        #expect(first?.supportsEffortConfig == true)
        #expect(second == first)
        #expect(firstDetector.detectCount == 1)
        #expect(secondDetector.detectCount == 0)
    }

    @Test
    func cacheHitWhenSignatureUnchanged() {
        let detector = FakeCapabilityDetector()
        let store = ToolCapabilityCacheStore(
            fileURL: makeCacheFileURL(),
            detector: detector
        )

        let executableURL = URL(fileURLWithPath: "/tmp/fake-codex")
        let first = store.capabilities(for: .codex, executableURL: executableURL, versionString: "codex-cli 0.104.0")
        let second = store.capabilities(for: .codex, executableURL: executableURL, versionString: "codex-cli 0.104.0")

        #expect(first == second)
        #expect(detector.detectCount == 1)
    }

    @Test
    func invalidatesWhenMtimeChanges() {
        let detector = FakeCapabilityDetector()
        let store = ToolCapabilityCacheStore(
            fileURL: makeCacheFileURL(),
            detector: detector
        )

        let executableURL = URL(fileURLWithPath: "/tmp/fake-codex")
        _ = store.capabilities(for: .codex, executableURL: executableURL, versionString: "codex-cli 0.104.0")

        detector.capabilitiesToReturn = ToolCapabilities(
            supportsModelFlag: true,
            supportsEffortConfig: true,
            supportedEffortValues: [.low]
        )
        detector.mtime = 200

        let updated = store.capabilities(for: .codex, executableURL: executableURL, versionString: "codex-cli 0.104.0")

        #expect(updated?.supportedEffortValues == [.low])
        #expect(detector.detectCount == 2)
    }

    @Test
    func invalidatesWhenSizeChanges() {
        let detector = FakeCapabilityDetector()
        let store = ToolCapabilityCacheStore(
            fileURL: makeCacheFileURL(),
            detector: detector
        )

        let executableURL = URL(fileURLWithPath: "/tmp/fake-codex")
        _ = store.capabilities(for: .codex, executableURL: executableURL, versionString: "codex-cli 0.104.0")

        detector.capabilitiesToReturn = ToolCapabilities(
            supportsModelFlag: true,
            supportsEffortConfig: false,
            supportedEffortValues: []
        )
        detector.size = 4_096

        let updated = store.capabilities(for: .codex, executableURL: executableURL, versionString: "codex-cli 0.104.0")

        #expect(updated?.supportsEffortConfig == false)
        #expect(detector.detectCount == 2)
    }

    @Test
    func invalidatesWhenVersionStringChanges() {
        let detector = FakeCapabilityDetector()
        let store = ToolCapabilityCacheStore(
            fileURL: makeCacheFileURL(),
            detector: detector
        )

        let executableURL = URL(fileURLWithPath: "/tmp/fake-codex")
        _ = store.capabilities(for: .codex, executableURL: executableURL, versionString: "codex-cli 0.103.0")

        detector.capabilitiesToReturn = ToolCapabilities(
            supportsModelFlag: true,
            supportsEffortConfig: true,
            supportedEffortValues: [.low, .medium, .high]
        )

        let updated = store.capabilities(for: .codex, executableURL: executableURL, versionString: "codex-cli 0.104.0")

        #expect(updated?.supportsEffortConfig == true)
        #expect(detector.detectCount == 2)
    }

    @Test
    func forceRefreshBypassesCacheAndUpdatesTimestamp() throws {
        let detector = FakeCapabilityDetector()
        let store = ToolCapabilityCacheStore(
            fileURL: makeCacheFileURL(),
            detector: detector
        )

        let executableURL = URL(fileURLWithPath: "/tmp/fake-codex")
        let first = try #require(
            store.cachedCapabilities(
                for: .codex,
                executableURL: executableURL,
                versionString: "codex-cli 0.104.0"
            )
        )

        detector.capabilitiesToReturn = ToolCapabilities(
            supportsModelFlag: true,
            supportsEffortConfig: false,
            supportedEffortValues: []
        )

        let refreshed = try #require(
            store.cachedCapabilities(
                for: .codex,
                executableURL: executableURL,
                versionString: "codex-cli 0.104.0",
                forceRefresh: true
            )
        )

        #expect(detector.detectCount == 2)
        #expect(refreshed.capabilities.supportsEffortConfig == false)
        #expect(refreshed.signature.lastCheckedAt > first.signature.lastCheckedAt)
    }

    @Test
    func cacheDeletionIsHandledAsColdStartWithoutFailure() throws {
        let detector = FakeCapabilityDetector()
        let fileURL = makeCacheFileURL()
        let executableURL = URL(fileURLWithPath: "/tmp/fake-codex")

        let firstStore = ToolCapabilityCacheStore(fileURL: fileURL, detector: detector)
        _ = firstStore.capabilities(for: .codex, executableURL: executableURL, versionString: "codex-cli 0.104.0")
        try? FileManager.default.removeItem(at: fileURL)

        detector.capabilitiesToReturn = ToolCapabilities(
            supportsModelFlag: true,
            supportsEffortConfig: false,
            supportedEffortValues: []
        )

        let secondStore = ToolCapabilityCacheStore(fileURL: fileURL, detector: detector)
        let refreshed = secondStore.capabilities(
            for: .codex,
            executableURL: executableURL,
            versionString: "codex-cli 0.104.0"
        )

        #expect(detector.detectCount == 2)
        #expect(refreshed?.supportsEffortConfig == false)
    }

    private func makeCacheFileURL() -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PromptImproverTests", isDirectory: true)
            .appendingPathComponent("ToolCapabilityCache-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("cli-discovery-cache.json")
    }
}

private final class FakeCapabilityDetector: ToolCapabilityDetecting {
    var detectCount = 0
    var mtime: TimeInterval = 100
    var size: UInt64 = 2_048
    var signatureTimestamp: TimeInterval = 1_000
    var capabilitiesToReturn = ToolCapabilities(
        supportsModelFlag: true,
        supportsEffortConfig: true,
        supportedEffortValues: [.low, .medium, .high]
    )

    func makeSignature(tool: Tool, executableURL: URL, versionString: String?) -> ToolBinarySignature? {
        defer { signatureTimestamp += 1 }
        return ToolBinarySignature(
            tool: tool,
            path: executableURL.path,
            versionString: versionString ?? "",
            mtime: mtime,
            size: size,
            lastCheckedAt: Date(timeIntervalSince1970: signatureTimestamp)
        )
    }

    func detectCapabilities(tool: Tool, executableURL: URL, signature: ToolBinarySignature) -> ToolCapabilities {
        detectCount += 1
        return capabilitiesToReturn
    }
}
