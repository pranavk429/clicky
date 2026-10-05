import XCTest
@testable import ClickyGemini

final class FakeTransportTests: XCTestCase {
    func testScriptedFramesArriveInOrder() async throws {
        let transport = FakeTransport(scriptedFrames: ["one", "two", "three"])
        let received = [try await transport.receive(), try await transport.receive(), try await transport.receive()]
        XCTAssertEqual(received.map { String(decoding: $0, as: UTF8.self) }, ["one", "two", "three"])
    }

    func testDeliverAfterReceiveHasStarted() async throws {
        let transport = FakeTransport()
        let receiveTask = Task { try await transport.receive() }
        await transport.deliver("late")
        let data = try await receiveTask.value
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "late")
    }

    func testCloseMakesReceiveThrowAndSendIsRecorded() async throws {
        let transport = FakeTransport()
        try await transport.connect()
        try await transport.send(Data("out".utf8))
        await transport.finishIncoming()
        do {
            _ = try await transport.receive()
            XCTFail("receive should throw after the incoming stream ends")
        } catch {
            XCTAssertEqual(error as? GeminiTransportError, .closed)
        }
        await transport.close()
        do {
            try await transport.send(Data("after-close".utf8))
            XCTFail("send should throw after close")
        } catch {
            XCTAssertEqual(error as? GeminiTransportError, .closed)
        }
        let sent = await transport.sentStrings()
        XCTAssertEqual(sent, ["out"])
    }

    func testSatisfiedWaiterDoesNotFlushOtherPendingWaiters() async throws {
        let transport = FakeTransport()
        let pending = Task { await transport.waitForSent(count: 2, timeout: 2) }
        let satisfied = Task { await transport.waitForSent(count: 1, timeout: 2) }
        // Let both waiters register (actor hop) before any send.
        try await Task.sleep(nanoseconds: 50_000_000)
        try await transport.send(Data("one".utf8))
        let satisfiedValue = await satisfied.value
        XCTAssertEqual(satisfiedValue, ["one"])
        // The defective code flushed every pending waiter when `satisfied`'s
        // cancelled timeout task woke up; `pending` must instead wait for its own timeout.
        let flushedEarly = await withTaskGroup(of: Bool.self) { group in
            group.addTask { _ = await pending.value; return true }
            group.addTask {
                try? await Task.sleep(nanoseconds: 250_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        XCTAssertFalse(flushedEarly, "satisfying one waiter must not flush another pending waiter")
    }
}
