import Foundation

struct StreamLineBuffer {
    private(set) var bufferedData = Data()
    let maxLineBytes: Int
    let maxBufferedBytes: Int

    init(maxLineBytes: Int = 8 * 1024 * 1024, maxBufferedBytes: Int = 32 * 1024 * 1024) {
        self.maxLineBytes = maxLineBytes
        self.maxBufferedBytes = maxBufferedBytes
    }

    mutating func append(_ incoming: Data) throws -> [Data] {
        if !incoming.isEmpty {
            bufferedData.append(incoming)
        }

        if bufferedData.count > maxBufferedBytes {
            throw PromptImproverError.bufferOverflow(limitBytes: maxBufferedBytes)
        }

        var lines: [Data] = []

        while let newlineIndex = bufferedData.firstIndex(of: 0x0A) {
            let line = bufferedData.prefix(upTo: newlineIndex)
            if line.count > maxLineBytes {
                throw PromptImproverError.lineTooLong(limitBytes: maxLineBytes)
            }
            lines.append(Data(line))
            bufferedData.removeSubrange(...newlineIndex)
        }

        if bufferedData.count > maxLineBytes {
            throw PromptImproverError.lineTooLong(limitBytes: maxLineBytes)
        }

        return lines
    }

    mutating func flushRemainder() throws -> Data? {
        guard !bufferedData.isEmpty else {
            return nil
        }

        if bufferedData.count > maxLineBytes {
            throw PromptImproverError.lineTooLong(limitBytes: maxLineBytes)
        }

        let remainder = bufferedData
        bufferedData.removeAll(keepingCapacity: false)
        return remainder
    }
}
