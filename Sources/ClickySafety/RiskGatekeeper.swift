import Foundation
/// One proposed action plus the local facts known about its target. Nothing
/// model-generated is trusted in this file: classification is deterministic
/// and local (spec §4.4 — the gate can never lower a tier).
public struct RiskContext: Equatable, Sendable {
    public var action: RiskAction
    public var targetRole: String?
    public var targetSubrole: String?
    public var targetTitle: String?
    public var targetAppBundleID: String?
    public var url: URL?
    public var isWebField: Bool
    public init(action: RiskAction, targetRole: String? = nil, targetSubrole: String? = nil,
                targetTitle: String? = nil, targetAppBundleID: String? = nil,
                url: URL? = nil, isWebField: Bool = false) {
        self.action = action; self.targetRole = targetRole; self.targetSubrole = targetSubrole
        self.targetTitle = targetTitle; self.targetAppBundleID = targetAppBundleID
        self.url = url; self.isWebField = isWebField
    }
}
/// Everything the tool router can ask the OS to do, in local terms.
public enum RiskAction: Equatable, Sendable {
    case read, navigate, click, typeText
    case openURL(parameters: Bool)
    case clipboardWrite, submitForm, sendCommunication, closeUnsavedDocument, trashFile
    case financial, terminalCommand, credentialEntry, systemSetting
}
/// Verdict for one proposed action, with the local rules that fired
/// (errata C6 requires logging which rule fired).
public struct RiskClassification: Equatable, Sendable {
    public let tier: RiskTier
    public let reasons: [String]
    public let isEgress: Bool
    public init(tier: RiskTier, reasons: [String], isEgress: Bool) {
        self.tier = tier; self.reasons = reasons; self.isEgress = isEgress
    }
}
/// The local 5-tier gatekeeper (spec §4.4; errata C5/C6). Egress actions
/// (navigation to a non-allowlisted domain, web-field typing, form submits,
/// clipboard writes, outbound messages) are Tier 3+ because they cannot be
/// un-sent. Allowlisted URLs with query parameters stay at their base Tier 2
/// (user-approved deviation from errata C5, 2026-10-06) unless the path,
/// query, or fragment carries a danger signal — a transactional/credential
/// keyword or an embedded / redirect URL shape — in which case they escalate
/// to Tier 3+ again. Plain search/watch URLs were escalating on every `?q=`
/// and timing out at the spoken-confirmation gate.
public enum RiskGatekeeper {
    public static func classify(_ context: RiskContext, modelRequestedTier: RiskTier? = nil) -> RiskClassification {
        if context.action == .read {
            // Inspection posts no hardware events, and macOS suppresses secure
            // field values to external clients; redaction/vision policy lives
            // downstream, not in the action gate.
            let tier = modelRequestedTier.map { max(.read, $0) } ?? .read
            var reasons = ["action:read"]
            if let requested = modelRequestedTier, requested > .read { reasons.append("model-raised:\(requested.rawValue)") }
            return RiskClassification(tier: tier, reasons: reasons, isEgress: false)
        }
        var tier = baseTier(context.action)
        var reasons = ["action:\(context.action)"]
        var egress = false
        switch context.action {
        case .openURL(let parameters):
            let allowlisted = context.url.map { NavigationPolicy.isAllowlisted($0) } ?? false
            if !allowlisted {
                tier = max(tier, .irreversible)
                reasons.append("egress:unknown-domain"); egress = true
            } else if let url = context.url, parameters || url.fragment != nil {
                // The caller's `parameters` flag tracks the query only; a
                // fragment-bearing URL is scanned too, because a fragment can
                // carry the same danger shapes.
                let danger = urlParameterDangerReasons(in: url)
                if danger.isEmpty {
                    // Deviation from errata C5 (user-approved, 2026-10-06):
                    // allowlisted search/watch URLs are ordinary navigation, not
                    // egress. Requiring spoken approval for every query parameter
                    // forced a Tier 3 gate on "google search ..." and timed out.
                    reasons.append("url:allowlisted-with-parameters")
                } else {
                    tier = max(tier, .irreversible)
                    reasons.append(contentsOf: danger); egress = true
                }
            }
        case .typeText where context.isWebField:
            tier = max(tier, .irreversible); reasons.append("egress:web-field-typing"); egress = true
        case .clipboardWrite, .submitForm, .sendCommunication:
            tier = max(tier, .irreversible); reasons.append("egress:\(context.action)"); egress = true
        default:
            break
        }
        if context.targetSubrole == "AXSecureTextField" { tier = .prohibited; reasons.append("subrole:AXSecureTextField") }
        if context.targetRole == "AXProtectedContent" { tier = .prohibited; reasons.append("role:AXProtectedContent") }
        if let bundle = context.targetAppBundleID, prohibitedBundleIDs.contains(bundle) {
            tier = .prohibited; reasons.append("app:\(bundle)")
        }
        if let title = context.targetTitle {
            if SafetyText.containsAny(prohibitedTitleKeywords, in: title) {
                tier = .prohibited; reasons.append("title:credential-or-terminal")
            } else if financialActions.contains(context.action),
                      SafetyText.containsAny(financialTitleKeywords, in: title) {
                tier = max(tier, .financial); reasons.append("title:financial")
            }
        }
        if let requested = modelRequestedTier, requested > tier { reasons.append("model-raised:\(requested.rawValue)") }
        tier = max(tier, modelRequestedTier ?? tier)
        return RiskClassification(tier: tier, reasons: reasons, isEgress: egress)
    }
    /// Danger signals scanned case-insensitively over an allowlisted URL's path,
    /// query, and fragment. Any hit makes the navigation egress Tier 3+ again:
    /// the transactional/credential keywords can drive a payment or secret
    /// flow, and embedded `http`, `url=`, `redirect` and `%2f%2f` are the
    /// open-redirect exfiltration shapes from errata C5. `URL.query` keeps its
    /// percent escapes, so an encoded `%2f%2f` is visible here; raw and decoded
    /// forms are scanned so encoded shapes (`%75rl=%68ttp...`, `%72edirect`)
    /// cannot hide behind their escapes. Decoding is bounded to two passes so
    /// double-encoded shapes (`%2575rl=%2568ttp`) cannot hide either, and a
    /// malformed escape leaves the raw scan intact.
    private static func urlParameterDangerReasons(in url: URL) -> [String] {
        var scan = url.path
        if let query = url.query { scan += "?" + query }
        if let fragment = url.fragment { scan += "#" + fragment }
        let decodedForms = decodedScanForms(of: scan)
        // `+` is the form-encoded space; the space form lets phrase keywords
        // match `q=pay+now` and `q=credit+card`.
        var keywordText = scan
        for form in decodedForms { keywordText += " " + form }
        keywordText += " " + scan.replacingOccurrences(of: "+", with: " ")
        var danger: [String] = []
        if SafetyText.containsAny(urlScanFinancialKeywords, in: keywordText) {
            danger.append("egress:url-danger:financial-keyword")
        }
        if SafetyText.containsAny(urlScanProhibitedKeywords, in: keywordText) {
            danger.append("egress:url-danger:prohibited-keyword")
        }
        // Structural checks run on every raw/decoded form. The raw form keeps
        // the literal `%2f%2f` check firing; the decoded forms catch encoded
        // shapes.
        let foldedForms = ([scan] + decodedForms).map(SafetyText.normalized)
        if foldedForms.contains(where: { $0.contains("http") }) {
            danger.append("egress:url-danger:embedded-url")
        }
        if foldedForms.contains(where: { $0.contains("url=") }) {
            danger.append("egress:url-danger:url-parameter")
        }
        if foldedForms.contains(where: { $0.contains("redirect") }) {
            danger.append("egress:url-danger:redirect")
        }
        if foldedForms.contains(where: { $0.contains("%2f%2f") }) {
            danger.append("egress:url-danger:encoded-slash")
        }
        return danger
    }
    /// Percent-decodes up to `maxPasses` times, stopping when decoding fails
    /// (malformed escape → nil) or the text stops changing. Two passes catch
    /// double-encoded shapes (`%2575rl` → `%75rl` → `url`) without opening an
    /// unbounded decode chain.
    private static func decodedScanForms(of text: String, maxPasses: Int = 2) -> [String] {
        var forms: [String] = []
        var current = text
        for _ in 0..<maxPasses {
            guard let decoded = current.removingPercentEncoding, decoded != current else { break }
            forms.append(decoded)
            current = decoded
        }
        return forms
    }
    private static func baseTier(_ action: RiskAction) -> RiskTier {
        switch action {
        case .read: return .read
        case .navigate, .click, .typeText, .openURL: return .reversible
        case .clipboardWrite, .submitForm, .sendCommunication, .closeUnsavedDocument, .trashFile: return .irreversible
        case .financial: return .financial
        case .terminalCommand, .credentialEntry, .systemSetting: return .prohibited
        }
    }
    static let prohibitedTitleKeywords = [
        "password", "passwd", "passcode", "passphrase", "pin", "otp", "one-time password",
        "sudo", "terminal", "keychain", "private key", "secret key",
        "पासवर्ड", "पिन", "ओटीपी", "पासकोड", "गुप्त कोड", "गुप्तशब्द",
    ]
    static let financialTitleKeywords = [
        "pay", "payment", "pay now", "checkout", "upi", "transfer", "purchase", "buy", "buy now",
        "recharge", "bill", "invoice",
        "भुगतान", "पेमेंट", "खरीद", "खरेदी", "बिल", "पैसे", "पैसा",
    ]
    /// URL-scan keyword sets (2026-10-06 quality-review fix): the URL scan
    /// flags transactional or credential intent only. Generic commerce
    /// vocabulary ("buy", "bill", "pay", "purchase", "recharge", "invoice",
    /// "transfer") and the bare "pin" made benign searches (`q=buy+iphone`,
    /// `q=electricity+bill`, `q=pune+pin+code`) escalate to Tier 3 and expire
    /// at the spoken-confirmation gate. Titles keep the broader lists above: a
    /// "Pay Now" button is a payment control, while "buy iphone" is an
    /// ordinary search.
    static let urlScanFinancialKeywords = [
        "payment", "pay now", "checkout", "upi", "netbanking", "net banking",
        "credit card", "card number", "cvv",
        "भुगतान", "पेमेंट", "पैसे", "पैसा",
    ]
    static let urlScanProhibitedKeywords = [
        "password", "passwd", "passcode", "passphrase", "otp", "one-time password",
        "sudo", "terminal", "keychain", "private key", "secret key",
        "पासवर्ड", "ओटीपी", "पासकोड", "गुप्त कोड", "गुप्तशब्द",
    ]
    static let prohibitedBundleIDs: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "com.apple.keychainaccess"]
    private static let financialActions: [RiskAction] = [.click, .submitForm, .financial]
}
/// URL allowlist for navigations (errata C5). A missing or non-allowlisted
/// host escalates the navigation to Tier 3+ spoken approval in the gatekeeper.
public enum NavigationPolicy {
    public static let allowlistedDomains: Set<String> = [
        "wikipedia.org", "google.com", "duckduckgo.com", "agmarknet.gov.in",
        "youtube.com", "github.com", "bing.com", "apple.com",
        // Common everyday destinations (live-log fix, 2026-10-06): without these,
        // "open LinkedIn" escalated to Tier 3 and expired at the confirmation gate.
        "linkedin.com", "reddit.com", "x.com", "twitter.com", "instagram.com",
        "facebook.com", "netflix.com", "amazon.com", "amazon.in",
        "stackoverflow.com", "chatgpt.com", "perplexity.ai",
    ]
    public static func isAllowlisted(_ url: URL, allowlist: Set<String> = allowlistedDomains) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return allowlist.contains { bare == $0 || bare.hasSuffix("." + $0) }
    }
}
/// Shared local text matching for the safety gates. Lowercases ASCII and
/// canonical-composes; never diacritic-folds, because folding strips
/// Devanagari matras and would break Hindi/Marathi keyword matching.
public enum SafetyText {
    public static func normalized(_ text: String) -> String { text.precomposedStringWithCanonicalMapping.lowercased() }
    public static func tokens(of text: String) -> [String] {
        normalized(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
    /// True when any keyword appears as a whole token; multi-word keywords also
    /// match as a substring and without spaces ("pay now" / "paynow").
    public static func containsAny(_ keywords: [String], in text: String) -> Bool {
        let folded = normalized(text)
        let tokenSet = Set(tokens(of: text))
        return keywords.contains { keyword in
            let foldedKeyword = normalized(keyword)
            if foldedKeyword.contains(" ") {
                return folded.contains(foldedKeyword)
                    || tokenSet.contains(foldedKeyword.replacingOccurrences(of: " ", with: ""))
            }
            return tokenSet.contains(foldedKeyword)
        }
    }
    /// Every token of `phrase` appears somewhere in `text` (order-free).
    public static func allTokensPresent(_ phrase: String, in text: String) -> Bool {
        let phraseTokens = tokens(of: phrase)
        guard !phraseTokens.isEmpty else { return false }
        return phraseTokens.allSatisfy(Set(tokens(of: text)).contains)
    }
}
