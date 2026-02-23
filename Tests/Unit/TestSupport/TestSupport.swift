import Foundation

enum TestSupport {
    static func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PromptImproverTests", isDirectory: true)
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func makeExecutableScript(name: String, script: String, prefix: String) throws -> URL {
        let directory = try makeTemporaryDirectory(prefix: prefix)
        let url = directory.appendingPathComponent(name)
        try writeExecutableScript(at: url, script: script)
        return url
    }

    static func writeExecutableScript(at url: URL, script: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    static func removeItemIfPresent(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

enum AsyncTestSupport {
    static func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollNanoseconds: UInt64 = 10_000_000,
        condition: @escaping () async -> Bool
    ) async -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        let timeout = start + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < timeout {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        return await condition()
    }
}
