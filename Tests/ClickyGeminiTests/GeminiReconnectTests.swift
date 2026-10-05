import ClickyCore
import XCTest
@testable import ClickyGemini

/// Deterministic clock: records requested delays, returns immediately.
actor RecordingSleeper: SleepProviding {
    private var delays: [TimeInterval] = []
    func sleep(seconds: TimeInterval) async throws { delays.append(seconds) }
    func recordedDelays() -> [TimeInterval] { delays }
}

actor TransportQueue {
    private var remaining: [FakeTransport]
    init(_ transports: [FakeTransport]) { remaining = transports }
    func next() throws -> any GeminiTransport {
        guard !remaining.isEmpty else { throw GeminiClientError.transportUnavailable }
        return remaining.removeFirst()
    }
}

final class GeminiReconnectTests: XCTestCase {
    private static let testSetup: @Sendable (String?) -> GeminiSetup = { handle in
        GeminiSetupBuilder.make(systemInstruction: "Test.", resumptionHandle: handle)
    }

    func testBackoffSequenceAndCap() {
        XCTAssertEqual(ReconnectPolicy.backoffDelay(attempt: 1), 0.5)
        XCTAssertEqual(ReconnectPolicy.backoffDelay(attempt: 2), 1.0)
        XCTAssertEqual(ReconnectPolicy.backoffDelay(attempt: 3), 2.0)
        XCTAssertEqual(ReconnectPolicy.backoffDelay(attempt: 9), 4.0)
    }

    func testGoAwayDelayLeavesTheTwoSecondReconnectBudget() {
        XCTAssertEqual(ReconnectPolicy.goAwayDelay(timeLeftSeconds: 10), 8)
        XCTAssertEqual(ReconnectPolicy.goAwayDelay(timeLeftSeconds: 1), 0)
        XCTAssertEqual(ReconnectPolicy.goAwayDelay(timeLeftSeconds: nil), 0)
    }

    func testCachesOnlyResumableHandlesAndResumesOnGoAway() async throws {
        let first = FakeTransport(scriptedFrames: [WireFrames.setupComplete,
                                                   WireFrames.resumptionUpdate(handle: "H1", resumable: true),
                                                   WireFrames.resumptionUpdate(handle: "H2", resumable: false),
                                                   WireFrames.goAway("10s")])
        let second = FakeTransport(scriptedFrames: [WireFrames.setupComplete])
        let queue = TransportQueue([first, second])
        let sleeper = RecordingSleeper()
        let notices = Recorder<String>()
        let client = GeminiLiveClient(transportFactory: { try await queue.next() },
                                      setupFactory: Self.testSetup,
                                      sleeper: sleeper,
                                      onNotice: { text in Task { await notices.record(text) } })
        try await client.start()
        let secondSetup = await second.waitForSent(count: 1, timeout: 3)
        XCTAssertEqual(secondSetup?.count, 1, "client must reconnect to the queued transport")
        XCTAssertTrue((secondSetup ?? []).first?.contains(#""handle":"H1""#) == true,
                      "H2 (resumable == false) must be ignored")
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(delays, [8], "goAway waits timeLeft − 2 s before reconnecting")
        let reconnectNotice = await notices.wait(matching: { $0 == "Reconnected." }, timeout: 3)
        XCTAssertNotNil(reconnectNotice)
        let state = await client.connectionState
        XCTAssertEqual(state, .ready)
        await client.stop(reason: .userToggle)
    }

    func testResumeFailureFallsBackToFreshSessionWithNotice() async throws {
        let first = FakeTransport(scriptedFrames: [WireFrames.setupComplete,
                                                   WireFrames.resumptionUpdate(handle: "H1", resumable: true)])
        let failing = FakeTransport()                                  // setup never completes -> timeout
        let fresh = FakeTransport(scriptedFrames: [WireFrames.setupComplete])
        let queue = TransportQueue([first, failing, failing, failing, fresh])
        let notices = Recorder<String>()
        let client = GeminiLiveClient(transportFactory: { try await queue.next() },
                                      setupFactory: Self.testSetup,
                                      setupTimeout: 0.05,
                                      sleeper: RecordingSleeper(),
                                      onNotice: { text in Task { await notices.record(text) } })
        try await client.start()
        await first.finishIncoming()
        let freshSetup = await fresh.waitForSent(count: 1, timeout: 5)
        XCTAssertTrue((freshSetup ?? []).first?.contains("handle") == false,
                      "the fallback session must be fresh (no handle)")
        let fallbackNotice = await notices.wait(matching: { $0.contains("fresh") }, timeout: 5)
        XCTAssertNotNil(fallbackNotice)
        await client.stop(reason: .userToggle)
    }

    func testDroppedConnectionFailsInFlightToolCallsClosed() async throws {
        let first = FakeTransport(scriptedFrames: [WireFrames.setupComplete, WireFrames.toolCall(id: "fc-1")])
        let second = FakeTransport(scriptedFrames: [WireFrames.setupComplete])
        let queue = TransportQueue([first, second])
        let markers = Recorder<GeminiMarker>()
        let handler = GatedToolHandler(gatedIDs: ["fc-1"])
        let client = GeminiLiveClient(transportFactory: { try await queue.next() },
                                      setupFactory: Self.testSetup,
                                      toolHandler: handler,
                                      sleeper: RecordingSleeper(),
                                      onMarker: { marker in Task { await markers.record(marker) } })
        try await client.start()
        let received = await markers.wait(matching: { $0 == .toolCallReceived(id: "fc-1") })
        XCTAssertNotNil(received)
        await first.finishIncoming()
        let dropped = await markers.wait(matching: { if case .toolCallDropped(let id, _) = $0 { return id == "fc-1" }; return false },
                                         timeout: 3)
        XCTAssertNotNil(dropped, "in-flight tool calls must fail-closed when the socket drops")
        await handler.release("fc-1")
        _ = await second.waitForSent(count: 1, timeout: 3)
        let secondSends = await second.sentStrings()
        XCTAssertFalse(secondSends.contains { $0.contains("fc-1") }, "no response may leak into the new session")
        await client.stop(reason: .userToggle)
    }
}
