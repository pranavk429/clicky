import ClickyCore
import XCTest
@testable import ClickyGemini

final class GeminiLiveClientTests: XCTestCase {
    private static let testSetup = GeminiSetupBuilder.make(systemInstruction: "Test.", tools: nil)

    private func makeClient(transport: FakeTransport,
                            handler: (any GeminiToolHandling)? = nil,
                            content: Recorder<GeminiServerContent>? = nil,
                            notices: Recorder<String>? = nil,
                            markers: Recorder<GeminiMarker>? = nil) -> GeminiLiveClient {
        GeminiLiveClient(
            transportFactory: { transport },
            setupFactory: { _ in Self.testSetup },
            toolHandler: handler,
            onServerContent: { value in if let content { Task { await content.record(value) } } },
            onNotice: { text in if let notices { Task { await notices.record(text) } } },
            onMarker: { marker in if let markers { Task { await markers.record(marker) } } })
    }

    func testNothingIsSentBeforeSetupComplete() async throws {
        let transport = FakeTransport()
        let client = makeClient(transport: transport)
        let startTask = Task { try await client.start() }
        let setupSend = await transport.waitForSent(count: 1)
        XCTAssertEqual(setupSend?.count, 1, "setup must be the first frame")
        let connecting = await client.connectionState
        XCTAssertEqual(connecting, .connecting)
        do {
            try await client.sendAudio(Data([0, 0]))
            XCTFail("audio must not be sent before setupComplete")
        } catch {
            XCTAssertEqual(error as? GeminiClientError, .notReady)
        }
        await transport.deliver(WireFrames.setupComplete)
        try await startTask.value
        let ready = await client.connectionState
        XCTAssertEqual(ready, .ready)
        try await client.sendAudio(Data([0, 0]))
        let sent = await transport.sentStrings()
        XCTAssertEqual(sent.count, 2)
        await client.stop(reason: .userToggle)
        let stopped = await client.connectionState
        XCTAssertEqual(stopped, .stopped(reason: .userToggle))
    }

    func testStopDuringConnectingPreservesTheUserStopReason() async throws {
        let transport = FakeTransport()
        let client = makeClient(transport: transport)
        let startTask = Task { try await client.start() }
        _ = await transport.waitForSent(count: 1)
        let connecting = await client.connectionState
        XCTAssertEqual(connecting, .connecting)
        await client.stop(reason: .userToggle)
        do {
            try await startTask.value
            XCTFail("start() must fail once the session is stopped mid-handshake")
        } catch {
            XCTAssertEqual(error as? GeminiClientError, .transportUnavailable)
        }
        let state = await client.connectionState
        XCTAssertEqual(state, .stopped(reason: .userToggle), "a stop during .connecting keeps the user's reason")
    }

    func testAudioChunkAndStreamEndMatchWireFormatWithMarkers() async throws {
        let transport = FakeTransport(scriptedFrames: [WireFrames.setupComplete])
        let markers = Recorder<GeminiMarker>()
        let client = makeClient(transport: transport, markers: markers)
        try await client.start()
        try await client.sendAudio(Data([0, 0, 0, 60]))
        try await client.sendAudioStreamEnd()
        let sent = await transport.sentStrings()
        XCTAssertEqual(sent.count, 3)
        XCTAssertTrue(sent[1].contains(#""mimeType":"audio/pcm;rate=16000""#))
        XCTAssertTrue(sent[1].contains(#""data":"AAAAPA==""#))
        XCTAssertEqual(sent[2], #"{"realtimeInput":{"audioStreamEnd":true}}"#)
        let streamEndMarker = await markers.wait(matching: { $0 == .audioStreamEndSent })
        XCTAssertNotNil(streamEndMarker)
        await client.stop(reason: .userToggle)
    }

    func testToolCallDispatchesAndSendsResponseWithMarkers() async throws {
        let transport = FakeTransport(scriptedFrames: [WireFrames.setupComplete, WireFrames.toolCall(id: "fc-9")])
        let markers = Recorder<GeminiMarker>()
        let handler = GatedToolHandler()
        let client = makeClient(transport: transport, handler: handler, markers: markers)
        try await client.start()
        let sent = await transport.waitForSent(count: 2)
        XCTAssertEqual(sent?.count, 2)
        XCTAssertTrue((sent?[1] ?? "").contains(#""id":"fc-9""#))
        XCTAssertTrue((sent?[1] ?? "").contains(#""scheduling":"WHEN_IDLE""#))
        let receivedMarker = await markers.wait(matching: { $0 == .toolCallReceived(id: "fc-9") })
        XCTAssertNotNil(receivedMarker)
        let responseSentMarker = await markers.wait(matching: { $0 == .toolResponseSent(id: "fc-9") })
        XCTAssertNotNil(responseSentMarker)
        let invoked = await handler.invokedIDs()
        XCTAssertEqual(invoked, ["fc-9"])
        await client.stop(reason: .userToggle)
    }

    func testTurnCompleteArrivesWhileToolHandlerIsBlocked() async throws {
        let transport = FakeTransport(scriptedFrames: [WireFrames.setupComplete,
                                                       WireFrames.toolCall(id: "fc-slow"),
                                                       WireFrames.turnComplete()])
        let content = Recorder<GeminiServerContent>()
        let handler = GatedToolHandler(gatedIDs: ["fc-slow"])
        let client = makeClient(transport: transport, handler: handler, content: content)
        try await client.start()
        let turnComplete = await content.wait(matching: { $0.turnComplete == true })
        XCTAssertNotNil(turnComplete, "the receive loop must not wait for the tool handler")
        await handler.release("fc-slow")
        let sent = await transport.waitForSent(count: 2)
        XCTAssertTrue((sent?[1] ?? "").contains("fc-slow"))
        await client.stop(reason: .userToggle)
    }

    func testToolCallCancellationDropsQueuedCall() async throws {
        let transport = FakeTransport(scriptedFrames: [WireFrames.setupComplete,
                                                       WireFrames.toolCall(id: "fc-drop"),
                                                       #"{"toolCallCancellation":{"ids":["fc-drop"]}}"#])
        let markers = Recorder<GeminiMarker>()
        let handler = GatedToolHandler(gatedIDs: ["fc-drop"])
        let client = makeClient(transport: transport, handler: handler, markers: markers)
        try await client.start()
        let dropped = await markers.wait(matching: { if case .toolCallDropped = $0 { return true }; return false })
        XCTAssertNotNil(dropped)
        let invoked = await handler.invokedIDs()
        XCTAssertEqual(invoked, [], "a cancelled call must not record a handler invocation")
        // If the handler had already started when the cancellation landed (gated
        // interleaving), releasing it must still not emit a response.
        await handler.release("fc-drop")
        let sent = await transport.sentStrings()
        XCTAssertEqual(sent.count, 1, "only setup — no response for a cancelled call")
        XCTAssertFalse(sent.contains { $0.contains("fc-drop") })
        await client.stop(reason: .userToggle)
    }

    func testToolCallCancellationBeforeDispatchNeverInvokesHandler() async throws {
        let transport = FakeTransport(scriptedFrames: [WireFrames.setupComplete,
                                                       #"{"toolCallCancellation":{"ids":["fc-x"]}}"#,
                                                       WireFrames.toolCall(id: "fc-x")])
        let markers = Recorder<GeminiMarker>()
        let handler = GatedToolHandler()
        let client = makeClient(transport: transport, handler: handler, markers: markers)
        try await client.start()
        let droppedMarker = await markers.wait(matching: { $0 == .toolCallDropped(id: "fc-x", reason: "cancelled by server") })
        XCTAssertNotNil(droppedMarker)
        let receivedMarker = await markers.wait(matching: { $0 == .toolCallReceived(id: "fc-x") })
        XCTAssertNotNil(receivedMarker)
        let invoked = await handler.invokedIDs()
        XCTAssertEqual(invoked, [], "the cancellation precedes the call — the handler must never run")
        let sent = await transport.sentStrings()
        XCTAssertEqual(sent.count, 1, "only setup — the cancelled call gets no response")
        XCTAssertFalse(sent.contains { $0.contains("fc-x") })
        await client.stop(reason: .userToggle)
    }

    func testGoAwayNotifiesAndCachesResumableHandle() async throws {
        let transport = FakeTransport(scriptedFrames: [WireFrames.setupComplete,
                                                       WireFrames.resumptionUpdate(handle: "H-1", resumable: true),
                                                       WireFrames.goAway("30s")])
        let notices = Recorder<String>()
        let client = makeClient(transport: transport, notices: notices)
        try await client.start()
        let closeNotice = await notices.wait(matching: { $0.contains("close") })
        XCTAssertNotNil(closeNotice, "goAway must surface a notice")
        let handle = await client.cachedResumptionHandle
        XCTAssertEqual(handle, "H-1")
        await client.stop(reason: .userToggle)
    }

    func testTransportLossSurfacesConnectionLostNotice() async throws {
        let transport = FakeTransport(scriptedFrames: [WireFrames.setupComplete])
        let notices = Recorder<String>()
        let client = makeClient(transport: transport, notices: notices)
        try await client.start()
        await transport.finishIncoming()
        let lostNotice = await notices.wait(matching: { $0.contains("Connection lost") })
        XCTAssertNotNil(lostNotice)
        await client.stop(reason: .userToggle)
    }

    func testInterruptedAndFirstAudioMarkers() async throws {
        let audioTurn = #"{"serverContent":{"modelTurn":{"parts":[{"inlineData":{"data":"AA==","mimeType":"audio/pcm;rate=24000"}}]}}}"#
        let barrier = #"{"toolCallCancellation":{"ids":["barrier"]}}"#
        let transport = FakeTransport(scriptedFrames: [WireFrames.setupComplete, audioTurn,
                                                       WireFrames.interrupted, audioTurn,
                                                       WireFrames.turnComplete(), audioTurn, barrier])
        let markers = Recorder<GeminiMarker>()
        let client = makeClient(transport: transport, markers: markers)
        try await client.start()
        let interruptedMarker = await markers.wait(matching: { $0 == .interruptedReceived })
        XCTAssertNotNil(interruptedMarker)
        let firstAudioMarker = await markers.wait(matching: { $0 == .firstAudioFrameReceived })
        XCTAssertNotNil(firstAudioMarker)
        let barrierDroppedMarker = await markers.wait(matching: { $0 == .toolCallDropped(id: "barrier", reason: "cancelled by server") })
        XCTAssertNotNil(barrierDroppedMarker)
        let firstAudioCount = await markers.all().filter { $0 == .firstAudioFrameReceived }.count
        XCTAssertEqual(firstAudioCount, 3, "first-audio fires once per turn — interruption and turnComplete both reset it")
        await client.stop(reason: .killSwitch)
    }
}
