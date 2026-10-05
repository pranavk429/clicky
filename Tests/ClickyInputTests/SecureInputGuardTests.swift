import ApplicationServices
import XCTest
@testable import ClickyInput

final class SecureInputGuardTests: XCTestCase {
    func testGlobalSecureInputBlocksKeystrokes() {
        let guardInstance = SecureInputGuard(elements: FakeElementServices(), isSecureInputEnabled: { true })
        let decision = guardInstance.evaluate()
        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.rule, .globalSecureEventInput)
    }

    func testGlobalSecureInputNeverBlocksPointerEvents() {   // errata B8
        let guardInstance = SecureInputGuard(elements: FakeElementServices(), isSecureInputEnabled: { true })
        for operation in [InputOperation.pointerClick, .pointerMove, .pointerDrag] {
            let decision = guardInstance.evaluate(operation: operation)
            XCTAssertTrue(decision.isAllowed)
            XCTAssertEqual(decision.rule, .globalSecureEventInput)
        }
    }

    func testSecureSubroleAndProtectedContentBlockKeystrokes() {
        let secure = FakeElementServices()
        secure.attributes[kAXSubroleAttribute as String] = "AXSecureTextField"
        secure.attributes[kAXRoleAttribute as String] = "AXTextField"
        let subroleDecision = SecureInputGuard(elements: secure, isSecureInputEnabled: { false })
            .evaluate(element: makeSentinelElement())
        XCTAssertFalse(subroleDecision.isAllowed)
        XCTAssertEqual(subroleDecision.rule, .secureTextFieldSubrole)

        let protected = FakeElementServices()
        protected.attributes[kAXRoleAttribute as String] = "AXProtectedContent"
        let protectedDecision = SecureInputGuard(elements: protected, isSecureInputEnabled: { false })
            .evaluate(element: makeSentinelElement())
        XCTAssertFalse(protectedDecision.isAllowed)
        XCTAssertEqual(protectedDecision.rule, .protectedContentRole)
    }

    func testCredentialKeywordsBlockButShippingDoesNot() {
        let password = FakeElementServices()
        password.attributes[kAXTitleAttribute as String] = "Password"
        let blocked = SecureInputGuard(elements: password, isSecureInputEnabled: { false })
            .evaluate(element: makeSentinelElement())
        XCTAssertFalse(blocked.isAllowed)
        XCTAssertEqual(blocked.rule, .credentialKeyword)

        let shipping = FakeElementServices()
        shipping.attributes[kAXTitleAttribute as String] = "Shipping Address"
        let allowed = SecureInputGuard(elements: shipping, isSecureInputEnabled: { false })
            .evaluate(element: makeSentinelElement())
        XCTAssertTrue(allowed.isAllowed)
        XCTAssertEqual(allowed.rule, .noRuleFired)

        XCTAssertTrue(CredentialHeuristic.matches(in: ["Enter your PIN"]))
        XCTAssertTrue(CredentialHeuristic.matches(in: ["पासवर्ड टाका"]))
        XCTAssertTrue(CredentialHeuristic.matches(in: ["OTP"]))
        XCTAssertFalse(CredentialHeuristic.matches(in: ["Shipping Address"]))
        XCTAssertFalse(CredentialHeuristic.matches(in: []))
    }
}
