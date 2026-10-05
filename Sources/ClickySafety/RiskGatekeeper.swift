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
/// The local 5-tier gatekeeper (spec §4.4; errata C5/C6). Egress actions (URL
/// with parameters, navigation to a non-allowlisted domain, web-field typing,
/// form submits, clipboard writes, outbound messages) are Tier 3+ because they
/// cannot be un-sent.
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
            if parameters || !allowlisted {
                tier = max(tier, .irreversible)
                reasons.append(parameters ? "egress:url-with-parameters" : "egress:unknown-domain"); egress = true
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
    static let prohibitedBundleIDs: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "com.apple.keychainaccess"]
    private static let financialActions: [RiskAction] = [.click, .submitForm, .financial]
}
/// URL allowlist for navigations (errata C5). A missing or non-allowlisted
/// host escalates the navigation to Tier 3+ spoken approval in the gatekeeper.
public enum NavigationPolicy {
    public static let allowlistedDomains: Set<String> = ["wikipedia.org", "google.com", "duckduckgo.com", "agmarknet.gov.in"]
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
