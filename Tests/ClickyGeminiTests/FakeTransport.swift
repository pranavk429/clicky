import Foundation
@testable import ClickyGemini

/// Wraps the stream iterator to allow mutating async iteration without actor isolation conflicts.
private final class IteratorBox: @unchecked Sendable {
    private var iterator: AsyncStream<Data>.Iterator

    init(_ iterator: AsyncStream<Data>.Iterator) {
        self.iterator = iterator
    }

    func next() async -> Data? {
        await iterator.next()
    }
}

/// Test double: scripted incoming frames, recorded outgoing frames, and
/// continuation-based waiting (no polling, no sleeps).
actor FakeTransport: GeminiTransport {
    private let continuation: AsyncStream<Data>.Continuation
    private let box: IteratorBox
    private var sentFrames: [Data] = []
    private var sendWaiters: [(id: Int, count: Int, continuation: CheckedContinuation<[String]?, Never>)] = []
    private var nextWaiterID = 0
    private var closed = false

    init(scriptedFrames: [String] = []) {
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        self.continuation = continuation
        self.box = IteratorBox(stream.makeAsyncIterator())
        for frame in scriptedFrames { continuation.yield(Data(frame.utf8)) }
    }

    func connect() async throws {}

    func send(_ data: Data) async throws {
        guard !closed else { throw GeminiTransportError.closed }
        sentFrames.append(data)
        resumeSatisfiedWaiters()
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
    func finishIncoming() { continuation.finish() }
    func sentStrings() -> [String] { sentFrames.map { String(decoding: $0, as: UTF8.self) } }

    /// Resolves when at least `count` frames have been sent; nil on this waiter's
    /// own timeout. Timeouts are per-waiter: one waiter timing out never flushes another.
    func waitForSent(count: Int, timeout: TimeInterval = 2) async -> [String]? {
        if sentFrames.count >= count { return sentStrings() }
        let id = nextWaiterID
        nextWaiterID += 1
        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            } catch {
                return
            }
            await self?.timeoutWaiter(id: id)
        }
        defer { timeoutTask.cancel() }
        return await withCheckedContinuation { continuation in
            sendWaiters.append((id, count, continuation))
        }
    }

    private func resumeSatisfiedWaiters() {
        let satisfied = sendWaiters.filter { sentFrames.count >= $0.count }
        sendWaiters.removeAll { sentFrames.count >= $0.count }
        for waiter in satisfied { waiter.continuation.resume(returning: sentStrings()) }
    }

    private func timeoutWaiter(id: Int) {
        guard let index = sendWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = sendWaiters.remove(at: index)
        waiter.continuation.resume(returning: nil)
    }
}
