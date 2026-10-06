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
            RiskContext(action: .openURL(parameters: true), url: URL(string: "https://wikipedia.org/w?q=pay+now")),
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
    func testOpenURLAllowlistedDomainWithoutQueryIsReversible() {
        for domain in ["youtube.com", "github.com", "bing.com", "apple.com",
                       "linkedin.com", "reddit.com", "x.com", "twitter.com",
                       "instagram.com", "facebook.com", "netflix.com",
                       "amazon.com", "amazon.in", "stackoverflow.com",
                       "chatgpt.com", "perplexity.ai"] {
            let context = RiskContext(action: .openURL(parameters: false),
                                      url: URL(string: "https://www.\(domain)/"))
            let result = RiskGatekeeper.classify(context)
            XCTAssertEqual(result.tier, .reversible, domain)
            XCTAssertFalse(result.isEgress, domain)
        }
    }
    func testNavigationAllowlistNewEntriesMatchHostsNotLookalikes() {
        XCTAssertTrue(NavigationPolicy.isAllowlisted(URL(string: "https://www.linkedin.com/feed/")!))
        XCTAssertTrue(NavigationPolicy.isAllowlisted(URL(string: "https://in.linkedin.com/")!))
        XCTAssertTrue(NavigationPolicy.isAllowlisted(URL(string: "https://www.amazon.in/s?k=swift")!))
        XCTAssertFalse(NavigationPolicy.isAllowlisted(URL(string: "https://linkedin.com.evil.com/")!))
        XCTAssertFalse(NavigationPolicy.isAllowlisted(URL(string: "https://notlinkedin.com/")!))
    }
    func testOpenURLAllowlistedDomainWithBenignQueryStaysReversible() {
        // Live-log fix (2026-10-06): allowlisted search/watch URLs with query
        // parameters are ordinary navigation, not egress — they were escalating
        // to Tier 3 and timing out at the spoken-confirmation gate.
        let cases: [(String, String)] = [
            ("https://www.google.com/search?q=swift", "google search"),
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "youtube watch"),
            ("https://www.amazon.in/s?k=swift", "amazon search"),
        ]
        for (raw, label) in cases {
            let context = RiskContext(action: .openURL(parameters: true), url: URL(string: raw))
            let result = RiskGatekeeper.classify(context)
            XCTAssertEqual(result.tier, .reversible, label)
            XCTAssertFalse(result.isEgress, label)
            XCTAssertTrue(result.reasons.contains("url:allowlisted-with-parameters"), label)
        }
    }
    func testOpenURLAllowlistedDangerKeywordsEscalate() {
        // Query text can drive exfiltration or a payment flow even on an
        // allowlisted host; the local keyword scan keeps that Tier 3+.
        let cases: [(String, String, String)] = [
            ("https://www.google.com/search?q=pay+now", "pay now", "egress:url-danger:financial-keyword"),
            ("https://www.google.com/search?q=checkout", "checkout", "egress:url-danger:financial-keyword"),
            ("https://www.google.com/search?q=upi", "upi", "egress:url-danger:financial-keyword"),
            ("https://www.google.com/search?q=password", "password", "egress:url-danger:prohibited-keyword"),
            ("https://www.google.com/search?q=otp", "otp", "egress:url-danger:prohibited-keyword"),
            // Percent-encoded Devanagari ("भुगतान", payment) must not hide the keyword.
            ("https://www.google.com/search?q=%E0%A4%AD%E0%A5%81%E0%A4%97%E0%A4%A4%E0%A4%BE%E0%A4%A8",
             "hindi payment (encoded)", "egress:url-danger:financial-keyword"),
        ]
        for (raw, label, reason) in cases {
            let context = RiskContext(action: .openURL(parameters: true), url: URL(string: raw))
            let result = RiskGatekeeper.classify(context)
            XCTAssertEqual(result.tier, .irreversible, label)
            XCTAssertTrue(result.isEgress, label)
            XCTAssertTrue(result.reasons.contains(reason), label)
        }
    }
    func testOpenURLGenericCommerceSearchesStayReversible() {
        // Quality-review fix (2026-10-06): generic commerce words and the bare
        // "pin" must not escalate ordinary searches — they re-created the
        // live-log timeout at the spoken-confirmation gate.
        let cases = [
            "https://www.google.com/search?q=buy+iphone",
            "https://www.google.com/search?q=electricity+bill",
            "https://www.google.com/search?q=pune+pin+code",
        ]
        for raw in cases {
            let context = RiskContext(action: .openURL(parameters: true), url: URL(string: raw))
            let result = RiskGatekeeper.classify(context)
            XCTAssertEqual(result.tier, .reversible, raw)
            XCTAssertFalse(result.isEgress, raw)
            XCTAssertTrue(result.reasons.contains("url:allowlisted-with-parameters"), raw)
        }
    }
    func testOpenURLTransactionalAndCredentialSearchesEscalate() {
        // The URL scan keeps transactional/credential intent: these still gate.
        let cases: [(String, String, String)] = [
            ("https://www.google.com/search?q=checkout", "checkout", "egress:url-danger:financial-keyword"),
            ("https://www.google.com/search?q=upi+transfer", "upi transfer", "egress:url-danger:financial-keyword"),
            ("https://www.google.com/search?q=netbanking", "netbanking", "egress:url-danger:financial-keyword"),
            ("https://www.google.com/search?q=credit+card", "credit card", "egress:url-danger:financial-keyword"),
            ("https://www.google.com/search?q=cvv", "cvv", "egress:url-danger:financial-keyword"),
            ("https://www.google.com/search?q=otp", "otp", "egress:url-danger:prohibited-keyword"),
            ("https://www.google.com/search?q=password+reset", "password reset", "egress:url-danger:prohibited-keyword"),
        ]
        for (raw, label, reason) in cases {
            let context = RiskContext(action: .openURL(parameters: true), url: URL(string: raw))
            let result = RiskGatekeeper.classify(context)
            XCTAssertEqual(result.tier, .irreversible, label)
            XCTAssertTrue(result.isEgress, label)
            XCTAssertTrue(result.reasons.contains(reason), "\(label): \(result.reasons)")
        }
    }
    func testOpenURLArbitraryQueryPayloadStaysReversibleByDesign() {
        // Residual risk, intentionally asserted: the user-approved carve-out
        // keeps an allowlisted host at Tier 2 no matter what arbitrary text the
        // query carries — the scan matches a bounded transactional/credential
        // keyword set, not intent. "transfer funds" is a plausible exfiltration
        // phrase and still stays Tier 2 by design; the mitigations are the
        // domain allowlist, the model needing a user voice command to navigate,
        // and the visible Ghost Cursor — not this scan.
        let context = RiskContext(action: .openURL(parameters: true),
                                  url: URL(string: "https://www.google.com/search?q=transfer+funds+to+account+9876543210"))
        let result = RiskGatekeeper.classify(context)
        XCTAssertEqual(result.tier, .reversible)
        XCTAssertFalse(result.isEgress)
        XCTAssertTrue(result.reasons.contains("url:allowlisted-with-parameters"))
    }
    func testOpenURLAllowlistedRedirectPatternsEscalate() {
        // Open-redirect and embedded-URL patterns in the query are egress even
        // on an allowlisted host (errata C5's exfiltration example).
        let cases: [(String, String, String)] = [
            ("https://www.google.com/search?q=swift&redirect=1", "redirect", "egress:url-danger:redirect"),
            ("https://www.google.com/search?url=https%3A%2F%2Fevil.com", "url param", "egress:url-danger:url-parameter"),
            ("https://www.google.com/search?q=http%3A%2F%2Fevil.com", "embedded http", "egress:url-danger:embedded-url"),
            ("https://www.google.com/search?q=%2f%2fevil.com", "encoded slashes", "egress:url-danger:encoded-slash"),
        ]
        for (raw, label, reason) in cases {
            let context = RiskContext(action: .openURL(parameters: true), url: URL(string: raw))
            let result = RiskGatekeeper.classify(context)
            XCTAssertEqual(result.tier, .irreversible, label)
            XCTAssertTrue(result.isEgress, label)
            XCTAssertTrue(result.reasons.contains(reason), label)
        }
    }
    func testOpenURLAllowlistedEncodedStructuralPatternsEscalate() {
        // A percent-encoded structural shape must not hide behind the raw scan:
        // `%75rl=%68ttp...` decodes to `url=http...` (the open-redirect
        // exfiltration shape from errata C5) and `%72edirect` to `redirect`.
        let cases: [(String, String, [String])] = [
            ("https://www.google.com/search?q=%75rl=%68ttp%3A//evil.com",
             "encoded url= + embedded http",
             ["egress:url-danger:url-parameter", "egress:url-danger:embedded-url"]),
            ("https://www.google.com/search?q=%72edirect%3D1",
             "encoded redirect", ["egress:url-danger:redirect"]),
        ]
        for (raw, label, reasons) in cases {
            let context = RiskContext(action: .openURL(parameters: true), url: URL(string: raw))
            let result = RiskGatekeeper.classify(context)
            XCTAssertEqual(result.tier, .irreversible, label)
            XCTAssertTrue(result.isEgress, label)
            for reason in reasons {
                XCTAssertTrue(result.reasons.contains(reason), "\(label): \(result.reasons)")
            }
        }
    }
    func testOpenURLFragmentIsScannedForDanger() {
        // The fragment is attacker-controllable text too: a danger keyword or a
        // double-encoded redirect shape after `#` must not bypass the scan just
        // because it sits past the query.
        let cases: [(String, String, String)] = [
            ("https://www.google.com/search?q=swift#otp", "fragment otp", "egress:url-danger:prohibited-keyword"),
            ("https://www.google.com/search?q=swift#checkout", "fragment checkout", "egress:url-danger:financial-keyword"),
            ("https://www.google.com/search#%2575rl=%2568ttp", "double-encoded fragment", "egress:url-danger:url-parameter"),
        ]
        for (raw, label, reason) in cases {
            let context = RiskContext(action: .openURL(parameters: true), url: URL(string: raw))
            let result = RiskGatekeeper.classify(context)
            XCTAssertEqual(result.tier, .irreversible, label)
            XCTAssertTrue(result.isEgress, label)
            XCTAssertTrue(result.reasons.contains(reason), "\(label): \(result.reasons)")
        }
        // A fragment-only URL must reach the scan even when the caller's
        // `parameters` flag is false (that flag tracks the query only).
        for (raw, label, reason) in cases {
            let context = RiskContext(action: .openURL(parameters: false), url: URL(string: raw))
            let result = RiskGatekeeper.classify(context)
            XCTAssertEqual(result.tier, .irreversible, "\(label) (no query flag)")
            XCTAssertTrue(result.isEgress, "\(label) (no query flag)")
            XCTAssertTrue(result.reasons.contains(reason), "\(label): \(result.reasons)")
        }
        let benign = RiskGatekeeper.classify(RiskContext(action: .openURL(parameters: false),
                                                         url: URL(string: "https://www.google.com/search#swift")))
        XCTAssertEqual(benign.tier, .reversible)
        XCTAssertFalse(benign.isEgress)
    }
    func testOpenURLDoubleEncodedDangerEscalates() {
        // One decode pass is not enough: `%2575rl=%2568ttp` decodes once to
        // `%75rl=%68ttp` and only twice to `url=http` (the errata C5
        // open-redirect shape). The bounded two-pass loop must catch that and
        // double-encoded keywords (`%256Ftp` → `%6Ftp` → `otp`).
        let cases: [(String, String, [String])] = [
            ("https://www.google.com/search?q=%2575rl=%2568ttp",
             "double-encoded url= + embedded http",
             ["egress:url-danger:url-parameter", "egress:url-danger:embedded-url"]),
            ("https://www.google.com/search?q=%256Ftp",
             "double-encoded otp", ["egress:url-danger:prohibited-keyword"]),
        ]
        for (raw, label, reasons) in cases {
            let context = RiskContext(action: .openURL(parameters: true), url: URL(string: raw))
            let result = RiskGatekeeper.classify(context)
            XCTAssertEqual(result.tier, .irreversible, label)
            XCTAssertTrue(result.isEgress, label)
            for reason in reasons {
                XCTAssertTrue(result.reasons.contains(reason), "\(label): \(result.reasons)")
            }
        }
    }
    func testOpenURLBenignEncodedQueryStaysReversible() {
        // Decoding exists only to find danger; a benign encoded parameter must
        // not escalate (regression guard for the structural dual-scan fix).
        let context = RiskContext(action: .openURL(parameters: true),
                                  url: URL(string: "https://www.google.com/search?q=swift%20concurrency"))
        let result = RiskGatekeeper.classify(context)
        XCTAssertEqual(result.tier, .reversible)
        XCTAssertFalse(result.isEgress)
        XCTAssertTrue(result.reasons.contains("url:allowlisted-with-parameters"))
    }
    func testOpenURLMalformedPercentAndLongURLsAreCrashFreeAndDeterministic() {
        // `%E0%A4` is an incomplete UTF-8 escape: removingPercentEncoding
        // returns nil, so classification must fall back to the raw scan without
        // crashing. Long inputs must likewise classify deterministically.
        let raws = [
            "https://www.google.com/search?q=%E0%A4",
            "https://www.google.com/search?q=" + String(repeating: "a", count: 4096),
        ]
        for raw in raws {
            let url = URL(string: raw)
            XCTAssertNotNil(url, "test fixture must parse")
            let context = RiskContext(action: .openURL(parameters: true), url: url)
            let first = RiskGatekeeper.classify(context)
            let second = RiskGatekeeper.classify(context)
            XCTAssertEqual(first, second)
            XCTAssertFalse(first.reasons.isEmpty)
        }
    }
    func testOpenURLNonAllowlistedDomainIsEgress() {
        let context = RiskContext(action: .openURL(parameters: false),
                                  url: URL(string: "https://example.com/"))
        let result = RiskGatekeeper.classify(context)
        XCTAssertEqual(result.tier, .irreversible)
        XCTAssertTrue(result.isEgress)
        XCTAssertTrue(result.reasons.contains("egress:unknown-domain"))
    }
    func testOpenURLNonAllowlistedDomainWithQueryIsEgress() {
        let context = RiskContext(action: .openURL(parameters: true),
                                  url: URL(string: "https://example.com/search?q=swift"))
        let result = RiskGatekeeper.classify(context)
        XCTAssertEqual(result.tier, .irreversible)
        XCTAssertTrue(result.isEgress)
        XCTAssertTrue(result.reasons.contains("egress:unknown-domain"))
    }
    func testSafetyTextWholeTokenMatching() {
        XCTAssertFalse(SafetyText.containsAny(["pin"], in: "Pinned note"))
        XCTAssertTrue(SafetyText.containsAny(["pin"], in: "Enter PIN"))
        XCTAssertTrue(SafetyText.containsAny(["pay now"], in: "PAYNOW.biz"))
        XCTAssertTrue(SafetyText.allTokensPresent("Project", in: "delete my project notes"))
        XCTAssertFalse(SafetyText.allTokensPresent("Terminal", in: "delete my project notes"))
    }
}
