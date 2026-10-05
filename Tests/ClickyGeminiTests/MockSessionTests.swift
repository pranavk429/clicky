import ClickyCore
import XCTest
@testable import ClickyGemini

final class MockSessionTests: XCTestCase {
    func testDemoScenarioJSONDecodes() throws {
        let scenario = try JSONDecoder().decode(MockSession.Scenario.self,
                                                from: Data(MockSession.demoScenarioJSON.utf8))
        XCTAssertEqual(scenario.name, "demo-delete-note")
        XCTAssertEqual(scenario.frames.count, 5)
        XCTAssertEqual(scenario.frames.first?.json, #"{"setupComplete":{}}"#)
    }

    func testMockReplayRunsThroughTheRealDispatchPath() async throws {
        let mock = try MockSession(scenarioJSON: MockSession.demoScenarioJSON, sleeper: ImmediateSleeper())
        let handler = GatedToolHandler()
        let transcripts = Recorder<String>()
        let markers = Recorder<GeminiMarker>()
        let client = GeminiLiveClient(
            transportFactory: { mock },
            setupFactory: { _ in GeminiSetupBuilder.make(systemInstruction: "Mock.") },
            toolHandler: handler,
            onServerContent: { content in
                if let text = content.inputTranscription?.text {
                    Task { await transcripts.record(text) }
                }
            },
            onMarker: { marker in Task { await markers.record(marker) } })
        try await client.start()
        let sent = await mock.waitForSent(count: 2)
        XCTAssertEqual(sent?.count, 2, "setup + toolResponse")
        XCTAssertTrue((sent?[0] ?? "").contains(#""model":"models/gemini-3.8-live""#))
        XCTAssertTrue((sent?[1] ?? "").contains(#""id":"demo-fc-1""#))
        let invoked = await handler.invokedIDs()
        XCTAssertEqual(invoked, ["demo-fc-1"], "the scripted tool call must reach the real handler")
        // Toolchain adaptation (recorded for Task 5.1): `await` inside an
        // XCTAssertNotNil autoclosure does not compile — hoist each awaited value.
        let toolResponseMarker = await markers.wait(matching: { $0 == .toolResponseSent(id: "demo-fc-1") })
        XCTAssertNotNil(toolResponseMarker)
        let transcription = await transcripts.wait(matching: { $0 == "Delete my project note" })
        XCTAssertNotNil(transcription)
        await client.stop(reason: .userToggle)
    }

    func testWaitForSentTimesOutWhenNothingWasSent() async throws {
        let mock = try MockSession(scenarioJSON: MockSession.demoScenarioJSON, sleeper: ImmediateSleeper())
        let sent = await mock.waitForSent(count: 1, timeout: 0.05)
        XCTAssertNil(sent)
    }
}
