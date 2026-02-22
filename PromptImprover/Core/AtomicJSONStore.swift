import Foundation

struct AtomicJSONStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func decode<T: Decodable>(_ type: T.Type, from fileURL: URL, using decoder: JSONDecoder = JSONDecoder()) throws -> T {
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(type, from: data)
    }

    func encodeAndWrite<T: Encodable>(_ value: T, to fileURL: URL, using encoder: JSONEncoder = JSONEncoder()) throws {
        let data = try encoder.encode(value)
        try write(data, to: fileURL)
    }

    func write(_ data: Data, to fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryURL = directory.appendingPathComponent(".\(fileURL.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try data.write(to: temporaryURL)

            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}
