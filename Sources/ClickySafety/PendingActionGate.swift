import Foundation
/// Spoken-confirmation gate for Tier 3–4 actions (spec §4.4; errata C1–C3;
/// Validation 03 §3.2). One pending action at a time; every failure mode is
/// fail-closed — no confirmation, no execution. Timing uses an injected clock
/// so the adjustable timeout, pause-on-speech and arm window are testable
/// without real waits.
public actor PendingActionGate {
    public struct PendingAction: Equatable, Sendable {
        public let id: UUID
        public let description: String
        public let tier: RiskTier
        public let anchors: [String]
        public let expectedAmount: Decimal?
        public init(id: UUID = UUID(), description: String, tier: RiskTier, anchors: [String], expectedAmount: Decimal? = nil) {
            self.id = id; self.description = description; self.tier = tier
            self.anchors = anchors; self.expectedAmount = expectedAmount
        }
    }
    public enum CancelReason: String, Equatable, Sendable { case negation, timeout, targetChanged, superseded, killed }
    public enum State: Equatable, Sendable {
        case idle
        case awaitingTurnComplete(PendingAction)
        case awaitingConfirmation(PendingAction, deadline: Date)
        case arming(PendingAction, confirmedAt: Date)
        case confirmed(PendingAction)
        case cancelled(PendingAction, CancelReason)
    }
    public enum SpeechOutcome: Equatable, Sendable { case ignored(String), cancelled(CancelReason), accepted }
    public enum ArmOutcome: Equatable, Sendable { case execute(PendingAction), abort(CancelReason) }
    public enum Tick: Equatable, Sendable {
        case idle
        case counting(remaining: TimeInterval)
        case expiringSoon(remaining: TimeInterval)
        case expired
    }
    public static let defaultTimeout: TimeInterval = 10, minimumTimeout: TimeInterval = 8, maximumTimeout: TimeInterval = 60
    public static let armWindow: TimeInterval = 0.5, financialLock: TimeInterval = 3, warningWindow: TimeInterval = 3
    public private(set) var state: State = .idle
    private let now: @Sendable () -> Date
    private var timeout: TimeInterval
    private var speakerIsActive = false
    private var speechPausedAt: Date?
    private var promptCompletedAt: Date?
    private var warnedSoon = false
    private static func clampTimeout(_ seconds: TimeInterval) -> TimeInterval {
        min(max(seconds, minimumTimeout), maximumTimeout)
    }
    public init(timeout: TimeInterval = PendingActionGate.defaultTimeout, now: @Sendable @escaping () -> Date = Date.init) {
        self.timeout = Self.clampTimeout(timeout); self.now = now
    }
    public var effectiveTimeout: TimeInterval { timeout }
    /// WCAG 2.2.1 timing adjustability; never below the 8 s floor (errata C2).
    public func setTimeout(_ seconds: TimeInterval) { timeout = Self.clampTimeout(seconds) }
    /// Start gating a new Tier 3–4 action; any action still pending is
    /// superseded (a new user intent replaces the old).
    public func present(_ action: PendingAction) {
        switch state {
        case .awaitingTurnComplete(let old), .awaitingConfirmation(let old, _), .arming(let old, _):
            state = .cancelled(old, .superseded)
        default:
            break
        }
        speechPausedAt = nil; promptCompletedAt = nil; warnedSoon = false
        state = .awaitingTurnComplete(action)
    }
    /// The model finished speaking the confirmation prompt; the timeout timer
    /// starts now — never earlier.
    public func promptTurnComplete() {
        guard case .awaitingTurnComplete(let action) = state else { return }
        let completedAt = now()
        promptCompletedAt = completedAt; warnedSoon = false
        state = .awaitingConfirmation(action, deadline: completedAt.addingTimeInterval(timeout))
    }
    /// Echo gate: true while the model's TTS is audible. A confirmation is
    /// accepted only while this is false — the read-back can never confirm
    /// itself.
    public func speakerActive(_ active: Bool) { speakerIsActive = active }
    /// User speech onset: pause the countdown (speech extends the window).
    public func userSpeechStarted() {
        guard case .awaitingConfirmation = state, speechPausedAt == nil else { return }
        speechPausedAt = now()
    }
    /// Countdown driver for the confirmation UI (call ~1 Hz): announces the
    /// imminent timeout once, then expires the pending action.
    public func tick() -> Tick {
        guard case .awaitingConfirmation(let action, let deadline) = state else { return .idle }
        let remaining = deadline.timeIntervalSince(speechPausedAt ?? now())
        if speechPausedAt == nil && remaining <= 0 { state = .cancelled(action, .timeout); return .expired }
        if remaining <= Self.warningWindow && !warnedSoon { warnedSoon = true; return .expiringSoon(remaining: max(0, remaining)) }
        return .counting(remaining: max(0, remaining))
    }
    /// Evaluate one finished user utterance (from input transcription).
    public func userSpoke(_ transcript: String) -> SpeechOutcome {
        let spokeAt = now()
        let pausedSince = speechPausedAt
        speechPausedAt = nil
        switch state {
        case .cancelled(_, let reason):
            return .cancelled(reason)
        case .idle, .confirmed:
            return .ignored("no pending action")
        case .arming(let action, _):
            if SafetyText.containsAny(Self.negations, in: transcript) {
                state = .cancelled(action, .negation); return .cancelled(.negation)
            }
            return .ignored("already confirmed; arm window in progress")
        case .awaitingTurnComplete(let action):
            if SafetyText.containsAny(Self.negations, in: transcript) {
                state = .cancelled(action, .negation); return .cancelled(.negation)
            }
            return .ignored("prompt not finished")
        case .awaitingConfirmation(let action, let deadline):
            let extended = pausedSince.map { deadline.addingTimeInterval(max(0, spokeAt.timeIntervalSince($0))) } ?? deadline
            if SafetyText.containsAny(Self.negations, in: transcript) {
                state = .cancelled(action, .negation); return .cancelled(.negation)
            }
            if extended != deadline { state = .awaitingConfirmation(action, deadline: extended) }
            if spokeAt >= extended { state = .cancelled(action, .timeout); return .cancelled(.timeout) }
            if speakerIsActive { return .ignored("echo gate not clear") }
            if !SafetyText.containsAny(Self.affirmatives, in: transcript) { return .ignored("no affirmative") }
            if action.tier == .financial {
                guard let expected = action.expectedAmount else { return .ignored("Tier 4 action without an expected amount") }
                if let promptAt = promptCompletedAt, spokeAt < promptAt.addingTimeInterval(Self.financialLock) {
                    return .ignored("financial lock")
                }
                guard AmountNormalizer.matches(expected: expected, in: transcript) else { return .ignored("amount mismatch") }
            } else {
                guard !action.anchors.isEmpty else { return .ignored("no anchors configured") }
                guard action.anchors.contains(where: { SafetyText.allTokensPresent($0, in: transcript) }) else {
                    return .ignored("no action echo")
                }
            }
            state = .arming(action, confirmedAt: spokeAt)
            return .accepted
        }
    }
    /// Hard ≥500 ms floor between confirmation and hardware execution, with
    /// target re-resolution inside the window (TOCTOU, errata C1). Reentrant:
    /// a kill switch or negation arriving while waiting cancels first.
    public func awaitArmAndRevalidate(id: UUID,
                                      revalidator: @Sendable (PendingAction) async -> Bool) async -> ArmOutcome {
        guard case .arming(let action, let confirmedAt) = state, action.id == id else {
            return .abort(abortReason(for: id))
        }
        let remaining = Self.armWindow - now().timeIntervalSince(confirmedAt)
        if remaining > 0 {
            do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
            catch { return .abort(abortReason(for: id)) }
        }
        guard case .arming(let armed, _) = state, armed.id == id else { return .abort(abortReason(for: id)) }
        let stillValid = await revalidator(armed)
        guard stillValid else { state = .cancelled(armed, .targetChanged); return .abort(.targetChanged) }
        guard case .arming(let final, _) = state, final.id == id else { return .abort(abortReason(for: id)) }
        state = .confirmed(final)
        return .execute(final)
    }
    /// Kill switch / new-intent / barge-in cancellation; valid in any state.
    public func cancel(reason: CancelReason = .killed) {
        switch state {
        case .awaitingTurnComplete(let action), .awaitingConfirmation(let action, _), .arming(let action, _):
            state = .cancelled(action, reason)
        default:
            break
        }
    }
    private func abortReason(for id: UUID) -> CancelReason {
        if case .cancelled(let action, let reason) = state, action.id == id { return reason }
        return .superseded
    }
    static let negations = [
        "no", "not", "nahi", "nahin", "nako", "naka", "ruko", "ruk", "thamba", "thamb", "stop", "cancel",
        "नहीं", "नाही", "नको", "नका", "रुको", "रुक", "थांब", "थांबा", "बंद", "कॅन्सल",
    ]
    static let affirmatives = [
        "yes", "yeah", "yep", "haan", "han", "ho", "hoy", "confirm", "go", "ok", "okay",
        "हाँ", "हां", "हो", "होय", "ठीक", "बरोबर",
    ]
}
