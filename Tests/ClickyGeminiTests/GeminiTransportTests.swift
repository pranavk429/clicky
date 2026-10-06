import XCTest
@testable import ClickyGemini

/// Framing contract of the production transport: JSON payloads are TEXT frames
/// (RFC 6455 opcode 0x1) — edge proxies in front of the Live gateway reject
/// BINARY — with a BINARY fallback for non-UTF-8 bytes.
final class GeminiTransportTests: XCTestCase {
    func testUTF8PayloadIsFramedAsTextWithIdenticalContent() throws {
        let json = Data(#"{"setup":{"model":"models/gemini-3.8-live"}}"#.utf8)
        guard case .string(let text) = URLSessionWebSocketTransport.message(for: json) else {
            return XCTFail("UTF-8 JSON must be framed as TEXT")
        }
        XCTAssertEqual(text, #"{"setup":{"model":"models/gemini-3.8-live"}}"#)
        XCTAssertEqual(Data(text.utf8), json)
    }

    func testNonUTF8PayloadFallsBackToBinary() {
        let bytes = Data([0xFF, 0xFE])
        guard case .data(let payload) = URLSessionWebSocketTransport.message(for: bytes) else {
            return XCTFail("non-UTF-8 bytes must fall back to BINARY")
        }
        XCTAssertEqual(payload, bytes)
    }
}
