import ApplicationServices
import Carbon
import Foundation

/// The operation a caller is about to synthesize. The guard's verdict is
/// operation-specific: secure input never blocks pointer events (errata B8).
public enum InputOperation: String, Equatable, Sendable {
    case keystrokes, pointerClick, pointerMove, pointerDrag
}

/// Which guard rule fired; logged with every decision (spec §4.2 rule 6).
public enum SecureInputRule: String, Equatable, Sendable {
    case noRuleFired
    case globalSecureEventInput
    case secureTextFieldSubrole
    case protectedContentRole
    case credentialKeyword
}

/// Typed verdict. `allowed` is authoritative; `ruleFired` is telemetry —
/// `.globalSecureEventInput` with `allowed == true` means "noted, not blocked"
/// (a pointer event posted while some password field holds secure input).
public struct SecureInputDecision: Equatable, Sendable {
    public let operation: InputOperation
    public let allowed: Bool
    public let ruleFired: SecureInputRule
    public let elementDescription: String?
    public var isAllowed: Bool { allowed }
    public var rule: SecureInputRule { ruleFired }
    init(operation: InputOperation, allowed: Bool, ruleFired: SecureInputRule, elementDescription: String? = nil) {
        self.operation = operation; self.allowed = allowed
        self.ruleFired = ruleFired; self.elementDescription = elementDescription
    }
}

/// `AXProtectedContent` has no public SDK constant (`AXRoleConstants.h` defines
/// only `kAXSecureTextFieldSubrole`), so the fallback role is a literal
/// (errata B1 lists it among the detection heuristics).
let axProtectedContentRole = "AXProtectedContent"

/// Last-line credential heuristics for the injection point (errata B1/C6).
/// Word-bounded so "Shipping" never matches "PIN".
public enum CredentialHeuristic {
    public static let pattern = "(?i)\\b(password|passcode|passwd|pin|otp)\\b|पासवर्ड|पिन|ओटीपी"
    public static func matches(in candidates: [String]) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return true } // fail closed
        return candidates.contains { candidate in
            regex.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)) != nil
        }
    }
}

/// Detects `IsSecureEventInputEnabled()` plus secure target fields before any
/// synthetic input. Keystrokes are refused while the global flag is on or the
/// target is an `AXSecureTextField` subrole / `AXProtectedContent` role /
/// credential-titled field. Pointer events are never blocked here — the
/// condition is only logged (errata B8). Fail-closed on an unreadable regex.
public struct SecureInputGuard: Sendable {
    private let elements: ElementServices
    private let isSecureInputEnabled: @Sendable () -> Bool

    public init(elements: ElementServices = SystemElementServices(),
                isSecureInputEnabled: @escaping @Sendable () -> Bool = { IsSecureEventInputEnabled() }) {
        self.elements = elements; self.isSecureInputEnabled = isSecureInputEnabled
    }

    public static func evaluate(element: AXUIElement? = nil) -> SecureInputDecision {
        SecureInputGuard().evaluate(element: element)
    }

    public func evaluate(element: AXUIElement? = nil, operation: InputOperation = .keystrokes) -> SecureInputDecision {
        let decision = evaluateInternal(operation: operation, targets: element.map { [$0] } ?? [])
        log(decision); return decision
    }
    public func decision(for operation: InputOperation, targets: [AXUIElement] = []) -> SecureInputDecision {
        let decision = evaluateInternal(operation: operation, targets: targets)
        log(decision); return decision
    }

    private func evaluateInternal(operation: InputOperation, targets: [AXUIElement]) -> SecureInputDecision {
        let secureGlobally = isSecureInputEnabled()
        if operation == .keystrokes {
            if secureGlobally { return SecureInputDecision(operation: operation, allowed: false, ruleFired: .globalSecureEventInput) }
            for target in targets { if let blocked = blockingRule(for: target, operation: operation) { return blocked } }
            return SecureInputDecision(operation: operation, allowed: true, ruleFired: .noRuleFired)
        }
        if secureGlobally { return SecureInputDecision(operation: operation, allowed: true, ruleFired: .globalSecureEventInput) }
        for target in targets where elements.stringAttribute(kAXSubroleAttribute as String, of: target) == (kAXSecureTextFieldSubrole as String) {
            return SecureInputDecision(operation: operation, allowed: true, ruleFired: .secureTextFieldSubrole, elementDescription: describe(target))
        }
        return SecureInputDecision(operation: operation, allowed: true, ruleFired: .noRuleFired)
    }

    private func blockingRule(for target: AXUIElement, operation: InputOperation) -> SecureInputDecision? {
        let subrole = elements.stringAttribute(kAXSubroleAttribute as String, of: target)
        if subrole == (kAXSecureTextFieldSubrole as String) {
            return SecureInputDecision(operation: operation, allowed: false, ruleFired: .secureTextFieldSubrole, elementDescription: describe(target))
        }
        if elements.stringAttribute(kAXRoleAttribute as String, of: target) == axProtectedContentRole {
            return SecureInputDecision(operation: operation, allowed: false, ruleFired: .protectedContentRole, elementDescription: describe(target))
        }
        let candidates = [kAXTitleAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute].compactMap { elements.stringAttribute($0 as String, of: target) }
        if CredentialHeuristic.matches(in: candidates) {
            return SecureInputDecision(operation: operation, allowed: false, ruleFired: .credentialKeyword, elementDescription: describe(target))
        }
        return nil
    }

    private func describe(_ target: AXUIElement) -> String {
        let role = elements.stringAttribute(kAXRoleAttribute as String, of: target) ?? "?"
        let subrole = elements.stringAttribute(kAXSubroleAttribute as String, of: target) ?? "-"
        let title = elements.stringAttribute(kAXTitleAttribute as String, of: target) ?? "-"
        return "role=\(role) subrole=\(subrole) title=\(title)"
    }

    private func log(_ decision: SecureInputDecision) {
        InputLog.secureInput.notice("\(decision.allowed ? "allowed" : "blocked", privacy: .public) op=\(decision.operation.rawValue, privacy: .public) rule=\(decision.ruleFired.rawValue, privacy: .public) target=\(decision.elementDescription ?? "-", privacy: .private)")
    }
}
