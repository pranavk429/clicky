import XCTest
@testable import ClickyGemini

final class GeminiProtocolTypesTests: XCTestCase {

    /// Exact wire shapes (spec §4.1; errata A3: one blob per 20–40 ms, never `mediaChunks`).
    private enum Fixtures {
        static let audioBlob = #"{"realtimeInput":{"audio":{"data":"AAAAPA==","mimeType":"audio/pcm;rate=16000"}}}"#
        static let videoBlob = #"{"realtimeInput":{"video":{"data":"AAAA","mimeType":"image/jpeg"}}}"#
        static let audioStreamEnd = #"{"realtimeInput":{"audioStreamEnd":true}}"#
        static let clientContent = #"{"clientContent":{"turns":[{"role":"user","parts":[{"text":"ping"}]}],"turnComplete":true}}"#
        static let setupComplete = #"{"setupComplete":{}}"#
        static let setup = #"{"setup":{"model":"models/gemini-3.8-live","generationConfig":{"responseModalities":["AUDIO"],"speechConfig":{"voiceConfig":{"prebuiltVoiceConfig":{"voiceName":"Aoede"}}}},"systemInstruction":{"parts":[{"text":"Reply briefly in the user's language."}]},"tools":[{"functionDeclarations":[{"name":"execute_action","description":"Execute one resolved UI action.","parameters":{"type":"object","properties":{}},"behavior":"NON_BLOCKING"}]}],"realtimeInputConfig":{"automaticActivityDetection":{"silenceDurationMs":400,"prefixPaddingMs":30,"startOfSpeechSensitivity":"START_OF_SPEECH_SENSITIVITY_HIGH","endOfSpeechSensitivity":"END_OF_SPEECH_SENSITIVITY_HIGH"}},"contextWindowCompression":{"slidingWindow":{}},"sessionResumption":{},"inputAudioTranscription":{}}}"#
        static let toolResponseSilent = #"{"toolResponse":{"functionResponses":[{"id":"fc-1","name":"execute_action","response":{"status":"ok"},"scheduling":"SILENT"}]}}"#
        static let serverContentAudio = #"{"serverContent":{"modelTurn":{"parts":[{"inlineData":{"data":"AA==","mimeType":"audio/pcm;rate=24000"}}]},"turnComplete":true}}"#
        static let serverContentInterrupted = #"{"serverContent":{"interrupted":true}}"#
        static let transcriptions = #"{"serverContent":{"inputTranscription":{"text":"सफारी उघड"},"outputTranscription":{"text":"Haan, dekhta hoon"}}}"#
        static let toolCall = #"{"toolCall":{"functionCalls":[{"id":"fc-1","name":"execute_action","args":{"target":"Save","amount":500}}]}}"#
        static let toolCallCancellation = #"{"toolCallCancellation":{"ids":["fc-1"]}}"#
        static let goAway = #"{"goAway":{"timeLeft":"12.5s"}}"#
        static let resumption = #"{"sessionResumptionUpdate":{"newHandle":"handle-abc","resumable":true}}"#
        static let unknown = #"{"mystery":{"payload":true}}"#
    }

    private func assertJSONEquals(_ actual: Data, _ expected: String,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let actualObject = try JSONSerialization.jsonObject(with: actual)
        let expectedObject = try JSONSerialization.jsonObject(with: Data(expected.utf8))
        let normalizedActual = try JSONSerialization.data(withJSONObject: actualObject, options: [.sortedKeys])
        let normalizedExpected = try JSONSerialization.data(withJSONObject: expectedObject, options: [.sortedKeys])
        XCTAssertEqual(String(decoding: normalizedActual, as: UTF8.self),
                       String(decoding: normalizedExpected, as: UTF8.self), file: file, line: line)
    }

    func testRealtimeInputBlobsEncodeExactWireFormat() throws {
        let audio = GeminiClientMessage.realtimeAudio(GeminiBlob(bytes: Data([0, 0, 0, 60]),
                                                                 mimeType: AudioChunkPacing.audioMimeType))
        try assertJSONEquals(try JSONEncoder().encode(audio), Fixtures.audioBlob)
        let video = GeminiClientMessage.realtimeVideo(GeminiBlob(data: "AAAA",
                                                                 mimeType: AudioChunkPacing.videoMimeType))
        try assertJSONEquals(try JSONEncoder().encode(video), Fixtures.videoBlob)
        try assertJSONEquals(try JSONEncoder().encode(GeminiClientMessage.audioStreamEnd), Fixtures.audioStreamEnd)
    }

    func testClientContentTurnEncodesExactWireFormat() throws {
        let message = GeminiClientMessage.clientContent(turns: [GeminiContent(role: "user", text: "ping")],
                                                        turnComplete: true)
        try assertJSONEquals(try JSONEncoder().encode(message), Fixtures.clientContent)
    }

    func testSetupMessageRoundTripsThroughExactFixture() throws {
        let setup = GeminiSetupBuilder.make(
            systemInstruction: "Reply briefly in the user's language.",
            tools: [GeminiTool(functionDeclarations: [
                GeminiFunctionDeclaration(name: "execute_action",
                                          description: "Execute one resolved UI action.",
                                          parameters: .object(["type": .string("object"),
                                                               "properties": .object([:])]))])])
        let encoded = try JSONEncoder().encode(GeminiClientMessage.setup(setup))
        try assertJSONEquals(encoded, Fixtures.setup)
        struct Envelope: Decodable { let setup: GeminiSetup }
        XCTAssertEqual(try JSONDecoder().decode(Envelope.self, from: encoded).setup, setup)
    }

    func testSetupWithResumptionHandleEncodesHandle() throws {
        let setup = GeminiSetupBuilder.make(systemInstruction: "Test.", resumptionHandle: "H-1")
        let encoded = try JSONEncoder().encode(GeminiClientMessage.setup(setup))
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains(#""sessionResumption":{"handle":"H-1"}"#))
    }

    func testToolResponseSchedulingSpellings() throws {
        for (scheduling, raw) in [(GeminiScheduling.silent, "SILENT"),
                                  (.whenIdle, "WHEN_IDLE"),
                                  (.interrupted, "INTERRUPTED")] {
            let message = GeminiClientMessage.toolResponse(GeminiToolResponse(functionResponses: [
                GeminiFunctionResponse(id: "fc-1", name: "execute_action",
                                       response: .object(["status": .string("ok")]), scheduling: scheduling)]))
            let encoded = try JSONEncoder().encode(message)
            XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("\"scheduling\":\"\(raw)\""))
        }
        XCTAssertNil(GeminiScheduling(rawValue: "INTERRUPT"), "enum spelling is INTERRUPTED (errata A9)")
    }

    func testToolResponseRoundTripsThroughExactFixture() throws {
        let response = GeminiToolResponse(functionResponses: [
            GeminiFunctionResponse(id: "fc-1", name: "execute_action",
                                   response: .object(["status": .string("ok")]), scheduling: .silent)])
        let encoded = try JSONEncoder().encode(GeminiClientMessage.toolResponse(response))
        try assertJSONEquals(encoded, Fixtures.toolResponseSilent)
        struct Envelope: Decodable { let toolResponse: GeminiToolResponse }
        XCTAssertEqual(try JSONDecoder().decode(Envelope.self, from: encoded).toolResponse, response)
    }

    func testServerSetupCompleteAndUnknownFrames() {
        XCTAssertEqual(GeminiServerMessage.decode(from: Data(Fixtures.setupComplete.utf8)), .setupComplete)
        XCTAssertNil(GeminiServerMessage.decode(from: Data(Fixtures.unknown.utf8)))
    }

    func testServerContentAudioTurnAndInterrupted() {
        let audio = GeminiServerMessage.decode(from: Data(Fixtures.serverContentAudio.utf8))
        guard case .serverContent(let content)? = audio else { return XCTFail("audio turn did not decode") }
        XCTAssertEqual(content.turnComplete, true)
        XCTAssertEqual(content.audioBase64Chunks, ["AA=="])
        let interrupted = GeminiServerMessage.decode(from: Data(Fixtures.serverContentInterrupted.utf8))
        guard case .serverContent(let contentB)? = interrupted else { return XCTFail("interrupted did not decode") }
        XCTAssertEqual(contentB.interrupted, true)
    }

    func testServerContentTranscriptions() {
        let decoded = GeminiServerMessage.decode(from: Data(Fixtures.transcriptions.utf8))
        guard case .serverContent(let content)? = decoded else { return XCTFail("transcriptions did not decode") }
        XCTAssertEqual(content.inputTranscription?.text, "सफारी उघड")
        XCTAssertEqual(content.outputTranscription?.text, "Haan, dekhta hoon")
    }

    func testToolCallAndCancellationDecode() {
        let decoded = GeminiServerMessage.decode(from: Data(Fixtures.toolCall.utf8))
        guard case .toolCall(let call)? = decoded else { return XCTFail("toolCall did not decode") }
        XCTAssertEqual(call.functionCalls.first?.id, "fc-1")
        XCTAssertEqual(call.functionCalls.first?.args?["target"], .string("Save"))
        XCTAssertEqual(call.functionCalls.first?.args?["amount"], .number(500))
        XCTAssertEqual(GeminiServerMessage.decode(from: Data(Fixtures.toolCallCancellation.utf8)),
                       .toolCallCancellation(ids: ["fc-1"]))
    }

    func testGoAwayAndResumptionUpdateDecode() {
        XCTAssertEqual(GeminiServerMessage.decode(from: Data(Fixtures.goAway.utf8)),
                       .goAway(timeLeftSeconds: 12.5))
        XCTAssertNil(GeminiGoAway.parseDurationSeconds("soon"))
        XCTAssertNil(GeminiGoAway.parseDurationSeconds(nil))
        XCTAssertEqual(GeminiServerMessage.decode(from: Data(Fixtures.resumption.utf8)),
                       .sessionResumptionUpdate(resumable: true, newHandle: "handle-abc"))
    }

    func testEndpointBuildsAPIKeyWebSocketURL() throws {
        let url = try XCTUnwrap(GeminiEndpoint.webSocketURL(apiKey: "TEST-KEY"))
        XCTAssertTrue(url.absoluteString.hasPrefix(
            "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"))
        XCTAssertTrue(url.absoluteString.contains("key=TEST-KEY"))
    }
}
