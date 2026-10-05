import XCTest
@testable import ClickyGemini

/// Day-0 live API spike — run once before any UI work (spec §4.1; Report 02 §5.2).
///
/// Run: `GEMINI_API_KEY=<key> swift test --filter LiveSpikeTests 2>&1 | tail -3`
///
/// Pass/fail criteria:
///   1. `setupComplete` within 10 s; a silent audio frame + `audioStreamEnd`
///      accepted with no error close for 5 s. Covers the sensitivity enum spelling:
///      if the server closes with an invalid-argument error, replace the two
///      rawValue constants in `GeminiAutomaticActivityDetection` — the single
///      definition site — and re-run.
///   2. `scheduling` top-level placement accepted: after a `toolResponse` with a
///      top-level scheduling value the session stays `.ready` for 5 s. If the
///      server closes instead, move `scheduling` into the `response` dictionary in
///      `GeminiFunctionResponse` (single site), re-run, and record a dated errata
///      note in the plan (AGENTS.md §9).
///   3. A non-empty resumable `sessionResumptionUpdate` handle arrives and is cached.
final class LiveSpikeTests: XCTestCase {

    private func makeClient(handler: (any GeminiToolHandling)? = nil,
                            markers: Recorder<GeminiMarker>? = nil) throws -> GeminiLiveClient {
        guard let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty else {
            throw XCTSkip("GEMINI_API_KEY not set — live spike skipped")
        }
        let transport = URLSessionWebSocketTransport(url: try XCTUnwrap(GeminiEndpoint.webSocketURL(apiKey: key)))
        return GeminiLiveClient(
            transportFactory: { transport },
            setupFactory: { handle in
                GeminiSetupBuilder.make(
                    systemInstruction: "Spike client. When the user says 'ping', call spike_ping without speaking.",
                    tools: [GeminiTool(functionDeclarations: [
                        GeminiFunctionDeclaration(name: "spike_ping", description: "Spike echo tool.",
                                                  parameters: .object(["type": .string("object"),
                                                                       "properties": .object([:])]))])],
                    resumptionHandle: handle)
            },
            toolHandler: handler,
            setupTimeout: 10,
            onMarker: { marker in if let markers { Task { await markers.record(marker) } } })
    }

    func testSetupHandshakeAudioStreamEndAndSensitivitySpelling() async throws {
        let client = try makeClient()
        addTeardownBlock { await client.stop(reason: .userToggle) }
        do {
            try await client.start()
        } catch {
            return XCTFail("""
                Setup failed within 10 s (\(error.localizedDescription)). If the close mentioned an invalid
                sensitivity value, apply the rawValue fallback documented in this file's
                header, then re-run.
                """)
        }
        try await client.sendAudioFrame([Int16](repeating: 0, count: 320))
        try await client.sendAudioStreamEnd()
        try await Task.sleep(nanoseconds: 5_000_000_000)
        let state = await client.connectionState
        XCTAssertEqual(state, .ready, "session left .ready within 5 s of audioStreamEnd")
        await client.stop(reason: .userToggle)
    }

    func testResumptionHandleArrives() async throws {
        let client = try makeClient()
        addTeardownBlock { await client.stop(reason: .userToggle) }
        try await client.start()
        try await client.sendTextTurn("Say ready.")   // induce generation; updates arrive sooner
        var handle: String?
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            handle = await client.cachedResumptionHandle
            if handle != nil { break }
        }
        XCTAssertNotNil(handle, "no resumable sessionResumptionUpdate within 20 s")
        await client.stop(reason: .userToggle)
    }

    func testSchedulingTopLevelPlacementAccepted() async throws {
        let markers = Recorder<GeminiMarker>()
        let client = try makeClient(handler: GatedToolHandler(), markers: markers)
        addTeardownBlock { await client.stop(reason: .userToggle) }
        try await client.start()
        var observedToolCall = false
        for _ in 0..<3 {
            try await client.sendTextTurn("ping")
            let received = await markers.wait(matching: { if case .toolCallReceived = $0 { return true }; return false },
                                              timeout: 5)
            if received != nil { observedToolCall = true; break }
        }
        guard observedToolCall else {
            throw XCTSkip("Inconclusive: the model did not issue spike_ping after 3 text prompts — re-run")
        }
        let responseSent = await markers.wait(matching: { if case .toolResponseSent = $0 { return true }; return false },
                                              timeout: 5)
        XCTAssertNotNil(responseSent, "client must send a toolResponse for the spike call")
        try await Task.sleep(nanoseconds: 5_000_000_000)
        let state = await client.connectionState
        XCTAssertEqual(state, .ready, """
            The server closed after a top-level `scheduling` field — apply the documented
            fallback (move `scheduling` into the response payload) and re-run.
            """)
        await client.stop(reason: .userToggle)
    }
}
