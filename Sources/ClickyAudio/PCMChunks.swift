import Foundation

/// Pure buffer math for the live audio path (Chunk 5.5 insertion): base64 wire
/// payloads ↔ 16-bit little-endian samples, and exact 20 ms frame feeding.
/// Chunk 10's `AudioStreamEngine` absorbs or retires this helper.
public enum PCMChunks {
    /// The wire frame the live slice feeds: 20 ms at 16 kHz.
    public static let defaultFrameSampleCount = 320

    public static func samples(fromBase64 base64: String) -> [Int16] {
        guard let data = Data(base64Encoded: base64) else { return [] }
        return samples(fromLittleEndianData: data)
    }
    public static func samples(fromBase64Chunks chunks: [String]) -> [Int16] {
        chunks.flatMap(samples(fromBase64:))
    }
    public static func samples(fromLittleEndianData data: Data) -> [Int16] {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return [] }
        var samples: [Int16] = []
        samples.reserveCapacity(bytes.count / 2)
        var index = 0
        while index + 1 < bytes.count {
            samples.append(Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8))
            index += 2
        }
        return samples
    }
    public static func littleEndianData(from samples: [Int16]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples { withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) } }
        return data
    }

    /// Accumulates arbitrary sample counts and yields exact-size frames; the
    /// remainder is carried until the next feed (the 20 ms chunk boundary).
    public struct FrameFeeder: Sendable {
        public let frameSampleCount: Int
        private var pending: [Int16] = []
        public init(frameSampleCount: Int = PCMChunks.defaultFrameSampleCount) {
            self.frameSampleCount = frameSampleCount
        }
        public mutating func feed(_ samples: [Int16]) -> [[Int16]] {
            pending.append(contentsOf: samples)
            var frames: [[Int16]] = []
            while pending.count >= frameSampleCount {
                frames.append(Array(pending.prefix(frameSampleCount)))
                pending.removeFirst(frameSampleCount)
            }
            return frames
        }
        public var remainder: [Int16] { pending }
    }
}
