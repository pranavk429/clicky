import Foundation

/// Local mock mode — the demo fallback (spec §4.1 fallback warning; Validation 01
/// §3.2 #9). Replays a scripted session through the REAL `GeminiLiveClient` and the
/// real injected tool handler (chunk 11 wires the AX path). Deliberately NOT
/// `gemini-3.1-flash-live-preview`: that model cannot do async function calling,
/// which this design depends on (errata A2).
public actor MockSession: GeminiTransport {
    public struct Frame: Codable, Equatable, Sendable {
        public var afterMs: Int
        public var json: String
    }

    public struct Scenario: Codable, Equatable, Sendable {
        public var name: String
        public var frames: [Frame]
    }

    /// JSON scenario fixture, kept as a literal so the demo path needs no bundle
    /// resources. One delete-note turn: transcription → tool call → narration.
    public static let demoScenarioJSON = #"""
    {
      "name": "demo-delete-note",
      "frames": [
        { "afterMs": 0,   "json": "{\"setupComplete\":{}}" },
        { "afterMs": 300, "json": "{\"serverContent\":{\"inputTranscription\":{\"text\":\"Delete my project note\"}}}" },
        { "afterMs": 200, "json": "{\"toolCall\":{\"functionCalls\":[{\"id\":\"demo-fc-1\",\"name\":\"execute_action\",\"args\":{\"intent\":\"delete_selected_note\"}}]}}" },
        { "afterMs": 200, "json": "{\"serverContent\":{\"modelTurn\":{\"parts\":[{\"text\":\"Yeh note Trash mein chala jayega — recover ho sakta hai.\"}]}}}" },
        { "afterMs": 400, "json": "{\"serverContent\":{\"turnComplete\":true}}" }
      ]
    }
    """#

    private var frames: [Frame]
    private let sleeper: any SleepProviding
    private var sentFrames: [Data] = []
    private var isClosed = false

    public init(scenarioJSON: String, sleeper: any SleepProviding = RealSleeper()) throws {
        let scenario = try JSONDecoder().decode(Scenario.self, from: Data(scenarioJSON.utf8))
        self.frames = scenario.frames
        self.sleeper = sleeper
    }

    public func connect() async throws {}

    public func send(_ data: Data) async throws {
        guard !isClosed else { throw GeminiTransportError.closed }
        sentFrames.append(data)
    }

    public func receive() async throws -> Data {
        guard !isClosed else { throw GeminiTransportError.closed }
        guard !frames.isEmpty else {
            // Exhausted: idle rather than simulate a drop; the app stops the session.
            while !isClosed { try? await Task.sleep(nanoseconds: 20_000_000) }
            throw GeminiTransportError.closed
        }
        let frame = frames.removeFirst()
        if frame.afterMs > 0 {
            try? await sleeper.sleep(seconds: Double(frame.afterMs) / 1000)
        }
        return Data(frame.json.utf8)
    }

    public func close() async { isClosed = true }

    public func sentStrings() -> [String] { sentFrames.map { String(decoding: $0, as: UTF8.self) } }

    /// Deterministic wait for tests: resolves when `count` frames were sent, nil on timeout.
    public func waitForSent(count: Int, timeout: TimeInterval = 2) async -> [String]? {
        let deadline = Date().addingTimeInterval(timeout)
        while sentFrames.count < count {
            if Date() > deadline { return nil }
            await Task.yield()
            try? await sleeper.sleep(seconds: 0.005)
        }
        return sentStrings()
    }
}
