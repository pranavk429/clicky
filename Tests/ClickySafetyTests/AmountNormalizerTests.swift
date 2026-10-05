import XCTest
@testable import ClickySafety
final class AmountNormalizerTests: XCTestCase {
    func testRequiredTriadNormalizesEqual() {
        XCTAssertEqual(AmountNormalizer.normalize("₹500"), Decimal(500))
        XCTAssertEqual(AmountNormalizer.normalize("paanch sau"), Decimal(500))
        XCTAssertEqual(AmountNormalizer.normalize("५००"), Decimal(500))
        XCTAssertEqual(AmountNormalizer.normalize("पाँच सौ"), Decimal(500))
    }
    func testDigitFormatsAndDevanagariDigits() {
        XCTAssertEqual(AmountNormalizer.normalize("Rs.1,250"), Decimal(1250))
        XCTAssertEqual(AmountNormalizer.normalize("1,50,000"), Decimal(150000))
        XCTAssertEqual(AmountNormalizer.normalize("२,५००"), Decimal(2500))
        XCTAssertEqual(AmountNormalizer.normalize("450.50"), Decimal(string: "450.50"))
        XCTAssertEqual(AmountNormalizer.extractAmounts(from: "confirm 500 rupees"), [Decimal(500)])
    }
    func testCompoundWordNumbers() {
        XCTAssertEqual(AmountNormalizer.normalize("दो हजार पाँच सौ"), Decimal(2500))
        XCTAssertEqual(AmountNormalizer.normalize("do hazaar paanch sau"), Decimal(2500))
        XCTAssertEqual(AmountNormalizer.normalize("पाचशे"), Decimal(500))
        XCTAssertEqual(AmountNormalizer.normalize("sau"), Decimal(100))
        XCTAssertEqual(AmountNormalizer.normalize("five hundred"), Decimal(500))
    }
    func testMatchesInsideTranscripts() {
        XCTAssertTrue(AmountNormalizer.matches(expected: 500, in: "Haan, paanch sau confirm"))
        XCTAssertTrue(AmountNormalizer.matches(expected: 500, in: "हाँ ५००"))
        XCTAssertTrue(AmountNormalizer.matches(expected: 2500, in: "confirm do hazaar paanch sau"))
        XCTAssertFalse(AmountNormalizer.matches(expected: 500, in: "confirm paanch hazaar"))
        XCTAssertFalse(AmountNormalizer.matches(expected: 500, in: "haan theek hai"))
    }
    func testNonAmountPhrases() {
        XCTAssertNil(AmountNormalizer.normalize("haan"))
        XCTAssertNil(AmountNormalizer.normalize(""))
        XCTAssertEqual(AmountNormalizer.extractAmounts(from: "trash it"), [])
    }
}
