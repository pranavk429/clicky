import XCTest
@testable import ClickySafety
final class RiskTierTests: XCTestCase {
    func testOrderingAndGateProperties() {
        XCTAssertTrue(RiskTier.read < RiskTier.reversible && RiskTier.financial < RiskTier.prohibited)
        XCTAssertFalse(RiskTier.reversible.requiresSpokenConfirmation)
        XCTAssertTrue(RiskTier.irreversible.requiresSpokenConfirmation && RiskTier.irreversible.requiresGhostCursor)
        XCTAssertFalse(RiskTier.reversible.requiresGhostCursor)
        XCTAssertTrue(RiskTier.prohibited.isBlocked && !RiskTier.financial.isBlocked)
    }
}
