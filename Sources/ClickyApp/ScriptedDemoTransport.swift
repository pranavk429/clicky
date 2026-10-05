import ClickyGemini
import Foundation

/// Wraps the stream iterator to allow mutating async iteration without actor
/// isolation conflicts (same reason as Tests/ClickyGeminiTests/FakeTransport.swift).
private final class ScriptedIteratorBox: @unchecked Sendable {
    private var iterator: AsyncStream<Data>.Iterator

    init(_ iterator: AsyncStream<Data>.Iterator) {
        self.iterator = iterator
    }

    func next() async -> Data? {
        await iterator.next()
    }
}

/// The scripted server side of the demo: incoming frames are handed out in the
/// order the runner delivers them; outgoing frames are recorded for inspection.
/// This actor holds no timing logic — the runner owns the timeline.
actor ScriptedDemoTransport: GeminiTransport {
    private let continuation: AsyncStream<Data>.Continuation
    private let box: ScriptedIteratorBox
    private var sentFrames: [Data] = []
    private var closed = false

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        self.continuation = continuation
        self.box = ScriptedIteratorBox(stream.makeAsyncIterator())
    }

    func connect() async throws {}

    func send(_ data: Data) async throws {
        guard !closed else { throw GeminiTransportError.closed }
        sentFrames.append(data)
    }

    func receive() async throws -> Data {
        guard let data = await box.next() else { throw GeminiTransportError.closed }
        return data
    }

    func close() async {
        closed = true
        continuation.finish()
    }

    func deliver(_ frame: String) { continuation.yield(Data(frame.utf8)) }
    func finish() { continuation.finish() }
    func sentStrings() -> [String] { sentFrames.map { String(decoding: $0, as: UTF8.self) } }
}
