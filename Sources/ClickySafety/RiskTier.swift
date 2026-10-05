import Foundation
/// The 5-tier risk scale (spec §4.4). Classification is local; the model can
/// request actions but never lower a tier.
public enum RiskTier: Int, Comparable, CaseIterable, Sendable {
    case read = 1, reversible = 2, irreversible = 3, financial = 4, prohibited = 5
    public static func < (lhs: RiskTier, rhs: RiskTier) -> Bool { lhs.rawValue < rhs.rawValue }
    public var requiresGhostCursor: Bool { self >= .irreversible }
    public var requiresSpokenConfirmation: Bool { self >= .irreversible }
    public var requiresAmountReadBack: Bool { self == .financial }
    public var isBlocked: Bool { self == .prohibited }
}
