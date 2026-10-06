import Foundation

/// Bounded FIFO for microphone frames captured while the Live handshake runs
/// (the post-wake "deaf window" fix). Only the single audio-forwarding task
/// touches an instance, so no locking is needed: pre-readiness frames append
/// here, and the readiness marker drains them in order before any later frame
/// is sent.
///
/// The bound keeps memory fixed if the handshake stalls: the newest ~3 s of
/// 20 ms frames survive and the oldest are dropped. Losing the start of a
/// degraded-network utterance is preferable to unbounded growth or a stall.
struct AudioFrameBuffer {
    /// ~3 s of 20 ms frames at 16 kHz (spec §4.1: 320 samples per 20 ms chunk).
    static let defaultCapacity = 150

    let capacity: Int
    private(set) var frames: [[Int16]] = []

    init(capacity: Int = defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    mutating func append(_ frame: [Int16]) {
        frames.append(frame)
        if frames.count > capacity {
            frames.removeFirst(frames.count - capacity)
        }
    }

    /// Returns every buffered frame oldest-first and empties the buffer.
    mutating func drain() -> [[Int16]] {
        defer { frames.removeAll() }
        return frames
    }
}
