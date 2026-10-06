import ApplicationServices
import CoreGraphics
import Foundation

/// Normalized cache identity (spec §4.5): role + subrole + title + description,
/// case/whitespace-normalized so AX strings from different apps collide correctly.
public struct CacheKey: Hashable, Sendable {
    public let role: String
    public let subrole: String
    public let title: String
    public let description: String

    public init(role: String, subrole: String, title: String, description: String) {
        self.role = Self.normalize(role)
        self.subrole = Self.normalize(subrole)
        self.title = Self.normalize(title)
        self.description = Self.normalize(description)
    }
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// One normalized AX element (spec §4.5 "CacheEntry = element ref, global
/// top-left CGRect, enabled flag, actions"). `value` carries
/// `kAXValueAttribute` text (search bars, text fields) so voice targets can
/// match a field's content — deliberately NOT part of `CacheKey` identity,
/// because it changes far more often than structure. `@unchecked Sendable`:
/// `element` is an immutable CF reference; mutation is confined to the cache actor.
public struct ElementSnapshot: @unchecked Sendable {
    public let element: AXUIElement
    public let key: CacheKey
    public let frame: CGRect        // global top-left (CG) coordinates, y down — AX's native space
    public let isEnabled: Bool
    public let isSecureField: Bool
    public let actions: [String]
    public let value: String

    /// Stored-value bound (characters): bounds cache memory for document-sized
    /// values; any label a voice query can match is far shorter.
    static let maxStoredValueLength = 500

    public init(element: AXUIElement, key: CacheKey, frame: CGRect,
                isEnabled: Bool, isSecureField: Bool, actions: [String], value: String = "") {
        self.element = element
        self.key = key
        self.frame = frame
        self.isEnabled = isEnabled
        self.isSecureField = isSecureField
        self.actions = actions
        self.value = value
    }
    public var normalizedPoint: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    /// Value projection for snapshot construction: secure fields retain nothing
    /// (errata B1 — credentials are never cached); all other values are truncated
    /// to `maxStoredValueLength`.
    static func storedValue(_ raw: String, isSecure: Bool) -> String {
        guard !isSecure else { return "" }
        return String(raw.prefix(maxStoredValueLength))
    }

    /// Errata B1: check `kAXSubroleAttribute` first (role is typically
    /// `AXTextField`); then spec §4.4 heuristics — `AXProtectedContent` plus
    /// whole-word title/placeholder keywords including Devanagari ("Spinner" stays out).
    public static func looksSecure(role: String?, subrole: String?, title: String?, placeholder: String?) -> Bool {
        if subrole == "AXSecureTextField" { return true }
        if role == "AXProtectedContent" { return true }
        let tokens = Set([title ?? "", placeholder ?? ""]
            .flatMap { $0.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) })
        let keywords: Set<String> = ["password", "passcode", "pin", "otp", "पासवर्ड", "पिन"]
        return !tokens.isDisjoint(with: keywords)
    }
}
