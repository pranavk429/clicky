import XCTest
@testable import ClickySafety
final class RiskGatekeeperTests: XCTestCase {
    func testReadsAreTierOne() {
        XCTAssertEqual(RiskGatekeeper.classify(RiskContext(action: .read)).tier, .read)
        // Inspection posts no events and macOS suppresses secure values to
        // external clients, so a read of a credential field stays Tier 1.
        let secure = RiskContext(action: .read, targetSubrole: "AXSecureTextField", targetTitle: "Password")
        XCTAssertEqual(RiskGatekeeper.classify(secure).tier, .read)
    }
    func testNavigationIsTierTwo() {
        let cases: [RiskContext] = [
            RiskContext(action: .navigate),
            RiskContext(action: .click, targetTitle: "Inbox"),
            RiskContext(action: .typeText, targetTitle: "Note body"),
            RiskContext(action: .openURL(parameters: false), url: URL(string: "https://en.wikipedia.org/wiki/Pune")),
        ]
        for context in cases { XCTAssertEqual(RiskGatekeeper.classify(context).tier, .reversible, "\(context)") }
    }
    func testEgressIsTierThreeAndFlagged() {
        let egressCases: [RiskContext] = [
            RiskContext(action: .openURL(parameters: true), url: URL(string: "https://wikipedia.org/w?q=x")),
            RiskContext(action: .openURL(parameters: false), url: URL(string: "https://evil.com/")),
            RiskContext(action: .openURL(parameters: false)),                     // no URL: fail closed
            RiskContext(action: .typeText, targetTitle: "Search", isWebField: true),
            RiskContext(action: .clipboardWrite),
            RiskContext(action: .submitForm),
            RiskContext(action: .sendCommunication, targetTitle: "Send email"),
        ]
        for context in egressCases {
            let result = RiskGatekeeper.classify(context)
            XCTAssertGreaterThanOrEqual(result.tier, .irreversible, "\(context)")
            XCTAssertTrue(result.isEgress, "\(context)")
        }
        let trash = RiskGatekeeper.classify(RiskContext(action: .trashFile, targetTitle: "Duplicate-Report.pdf"))
        XCTAssertEqual(trash.tier, .irreversible)      // Trash-routed deletion is recoverable but gated
        XCTAssertFalse(trash.isEgress)
        XCTAssertEqual(RiskGatekeeper.classify(RiskContext(action: .closeUnsavedDocument)).tier, .irreversible)
    }
    func testProhibitedTargetsAreTierFive() {
        let cases: [(RiskContext, String)] = [
            (RiskContext(action: .terminalCommand, targetTitle: "zsh"), "terminal action"),
            (RiskContext(action: .credentialEntry, targetTitle: "Login"), "credential action"),
            (RiskContext(action: .systemSetting, targetTitle: "Security"), "system security settings"),
            (RiskContext(action: .typeText, targetSubrole: "AXSecureTextField"), "secure subrole"),
            (RiskContext(action: .click, targetRole: "AXProtectedContent"), "protected content"),
            (RiskContext(action: .click, targetAppBundleID: "com.apple.Terminal"), "terminal app"),
            (RiskContext(action: .click, targetTitle: "sudo: authenticate"), "sudo keyword"),
            (RiskContext(action: .click, targetTitle: "Enter password"), "password keyword"),
            (RiskContext(action: .click, targetTitle: "अपना पासवर्ड डालें"), "hindi password"),
            (RiskContext(action: .click, targetTitle: "पासवर्ड टाका"), "marathi password"),
            (RiskContext(action: .click, targetTitle: "OTP verify"), "otp keyword"),
            (RiskContext(action: .click, targetTitle: "ओटीपी टाका"), "marathi otp"),
        ]
        for (context, label) in cases { XCTAssertEqual(RiskGatekeeper.classify(context).tier, .prohibited, label) }
    }
    func testFinancialTargetsAreTierFour() {
        let cases: [(RiskContext, String)] = [
            (RiskContext(action: .click, targetTitle: "Pay Now"), "english pay"),
            (RiskContext(action: .submitForm, targetTitle: "भुगतान करें"), "hindi payment"),
            (RiskContext(action: .click, targetTitle: "पेमेंट करा"), "marathi payment"),
            (RiskContext(action: .click, targetTitle: "Buy now"), "buy"),
            (RiskContext(action: .financial), "financial action"),
        ]
        for (context, label) in cases { XCTAssertEqual(RiskGatekeeper.classify(context).tier, .financial, label) }
    }
    func testModelCanRaiseButNeverLower() {
        XCTAssertEqual(RiskGatekeeper.classify(RiskContext(action: .financial), modelRequestedTier: .read).tier, .financial)
        XCTAssertEqual(RiskGatekeeper.classify(RiskContext(action: .credentialEntry), modelRequestedTier: .reversible).tier, .prohibited)
        XCTAssertEqual(RiskGatekeeper.classify(RiskContext(action: .navigate), modelRequestedTier: .prohibited).tier, .prohibited)
    }
    func testNavigationAllowlist() {
        XCTAssertTrue(NavigationPolicy.isAllowlisted(URL(string: "https://en.wikipedia.org/wiki/Pune")!))
        XCTAssertTrue(NavigationPolicy.isAllowlisted(URL(string: "https://www.google.com/search?q=pune")!))
        XCTAssertFalse(NavigationPolicy.isAllowlisted(URL(string: "https://evil.com/x?y=1")!))
        XCTAssertFalse(NavigationPolicy.isAllowlisted(URL(string: "https://evilwikipedia.org/")!))
        XCTAssertFalse(NavigationPolicy.isAllowlisted(URL(string: "https://wikipedia.org.evil.com/")!))
        XCTAssertFalse(NavigationPolicy.isAllowlisted(URL(string: "not-a-url")!))
    }
    func testSafetyTextWholeTokenMatching() {
        XCTAssertFalse(SafetyText.containsAny(["pin"], in: "Pinned note"))
        XCTAssertTrue(SafetyText.containsAny(["pin"], in: "Enter PIN"))
        XCTAssertTrue(SafetyText.containsAny(["pay now"], in: "PAYNOW.biz"))
        XCTAssertTrue(SafetyText.allTokensPresent("Project", in: "delete my project notes"))
        XCTAssertFalse(SafetyText.allTokensPresent("Terminal", in: "delete my project notes"))
    }
}
