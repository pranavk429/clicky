import XCTest
@testable import ClickyInput
final class UnicodeChunkerTests: XCTestCase {
    func testCapAndASCIISplit() {
        XCTAssertEqual(UnicodeChunker.chunk("hello"), ["hello"])
        XCTAssertEqual(UnicodeChunker.chunk(String(repeating: "a", count: 20)), [String(repeating: "a", count: 20)])
        XCTAssertEqual(UnicodeChunker.chunk(String(repeating: "a", count: 21)), [String(repeating: "a", count: 20), "a"])
    }
    func testNeverSplitsGraphemeClusters() {
        let conjunct = "\u{0915}\u{094D}\u{0937}"                      // क्ष — one cluster, 3 UTF-16 units
        XCTAssertEqual(UnicodeChunker.chunk(String(repeating: "a", count: 18) + conjunct),
                       [String(repeating: "a", count: 18), conjunct])
        let flag = "🇮🇳"                                               // 2 surrogate pairs
        let chunks = UnicodeChunker.chunk(String(repeating: "a", count: 18) + flag)
        XCTAssertEqual(chunks, [String(repeating: "a", count: 18), flag])
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= 20 })
        let family = "👨‍👩‍👧‍👦"                                       // ZWJ sequence, 11 units
        XCTAssertEqual(UnicodeChunker.chunk(String(repeating: "a", count: 10) + family),
                       [String(repeating: "a", count: 10), family])
    }
    func testDevanagariRoundTrip() {
        let s = "नमस्ते, सफारी उघड आणि पुण्याचे हवामान शोध."
        XCTAssertEqual(UnicodeChunker.chunk(s).joined(), s)
        XCTAssertTrue(UnicodeChunker.chunk(s).allSatisfy { $0.utf16.count <= 20 })
    }
}
