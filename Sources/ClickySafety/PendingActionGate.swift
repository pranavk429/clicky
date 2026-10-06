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
    /// Outcome of an on-screen card button decision (direct, non-voice input).
    public enum DirectDecision: Equatable, Sendable { case accepted, latched, ignored(String) }
    /// Which local input channel latched an early affirmative, so the adapter
    /// can label the confirmation source correctly (voice vs on-screen tap).
    public enum EarlyLatchSource: Equatable, Sendable { case voice, direct }
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
    /// Latched early affirmative captured while the model was still speaking the
    /// prompt. `promptTurnComplete()` consumes it (fresh latch → arm), and
    /// present/negation/timeout clear it. Financial actions never latch: the
    /// amount read-back cannot have been heard before the prompt completes.
    private var earlyAffirmativeAt: Date?
    /// Which local channel produced the latch above; nil whenever there is no
    /// latch. Mirrors the latch lifecycle so the adapter can label the
    /// confirmation source correctly.
    public private(set) var earlyLatchSource: EarlyLatchSource?
    private static func clampTimeout(_ seconds: TimeInterval) -> TimeInterval {
        min(max(seconds, minimumTimeout), maximumTimeout)
    }
    public init(timeout: TimeInterval = PendingActionGate.defaultTimeout, now: @Sendable @escaping () -> Date = { Date() }) {
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
        speechPausedAt = nil; promptCompletedAt = nil; warnedSoon = false; clearEarlyLatch()
        state = .awaitingTurnComplete(action)
    }
    /// The model finished speaking the confirmation prompt; the timeout timer
    /// starts now — never earlier. Returns true when a fresh early affirmative
    /// was latched: the action arms immediately at completion time (the caller
    /// still runs `awaitArmAndRevalidate`, the only execution path). A stale
    /// latch (older than the action timeout) is dropped.
    @discardableResult
    public func promptTurnComplete() -> Bool {
        guard case .awaitingTurnComplete(let action) = state else { return false }
        let completedAt = now()
        promptCompletedAt = completedAt; warnedSoon = false
        let latchedAt = earlyAffirmativeAt
        clearEarlyLatch()
        if let latchedAt, completedAt.timeIntervalSince(latchedAt) <= timeout {
            state = .arming(action, confirmedAt: completedAt)
            return true
        }
        state = .awaitingConfirmation(action, deadline: completedAt.addingTimeInterval(timeout))
        return false
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
        if speechPausedAt == nil && remaining <= 0 {
            clearEarlyLatch()
            state = .cancelled(action, .timeout); return .expired
        }
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
                clearEarlyLatch()
                state = .cancelled(action, .negation); return .cancelled(.negation)
            }
            return .ignored("already confirmed; arm window in progress")
        case .awaitingTurnComplete(let action):
            if SafetyText.containsAny(Self.negations, in: transcript) {
                clearEarlyLatch()
                state = .cancelled(action, .negation); return .cancelled(.negation)
            }
            guard SafetyText.containsAny(Self.affirmatives, in: transcript) else {
                return .ignored("prompt not finished")
            }
            if speakerIsActive { return .ignored("echo gate not clear") }
            // Financial actions never latch: the amount read-back has not
            // happened yet, so the confirmation cannot be trusted (Tier 4).
            guard action.tier != .financial else { return .ignored("prompt not finished") }
            // The user answered while the model was still speaking the prompt;
            // keep the decision instead of dropping it and timing out.
            earlyAffirmativeAt = spokeAt; earlyLatchSource = .voice
            return .ignored("early affirmative latched until the prompt completes")
        case .awaitingConfirmation(let action, let deadline):
            let extended = pausedSince.map { deadline.addingTimeInterval(max(0, spokeAt.timeIntervalSince($0))) } ?? deadline
            if SafetyText.containsAny(Self.negations, in: transcript) {
                clearEarlyLatch()
                state = .cancelled(action, .negation); return .cancelled(.negation)
            }
            if extended != deadline { state = .awaitingConfirmation(action, deadline: extended) }
            if spokeAt >= extended {
                clearEarlyLatch()
                state = .cancelled(action, .timeout); return .cancelled(.timeout)
            }
            if speakerIsActive { return .ignored("echo gate not clear") }
            if !SafetyText.containsAny(Self.affirmatives, in: transcript) { return .ignored("no affirmative") }
            if action.tier == .financial {
                guard let expected = action.expectedAmount else { return .ignored("Tier 4 action without an expected amount") }
                // Fail closed: without a prompt-completion timestamp the
                // read-back lock cannot be verified, so the confirmation is
                // refused rather than allowed through.
                guard let promptAt = promptCompletedAt else { return .ignored("financial lock") }
                if spokeAt < promptAt.addingTimeInterval(Self.financialLock) {
                    return .ignored("financial lock")
                }
                guard AmountNormalizer.matches(expected: expected, in: transcript) else { return .ignored("amount mismatch") }
            }
            // Spec §4.4 script: the completed prompt already named the action and
            // target ("Say Haan to confirm, or Ruko to cancel"); a clear
            // affirmative is sufficient for Tier 3. Negation won above; the echo
            // gate and the arm window/revalidation still apply. (The previous
            // anchor-echo requirement was stricter than the spec's validated
            // script and made a bare "Haan" silently fail.)
            state = .arming(action, confirmedAt: spokeAt)
            return .accepted
        }
    }
    /// On-screen card confirmation (direct input, not voice). Mirrors
    /// `userSpoke`'s state machine: the Tier 4 financial lock still applies, an
    /// early tap during the prompt latches exactly like an early "Haan", and
    /// the arm window + TOCTOU revalidation remain the only execution path.
    @discardableResult
    public func userConfirmed() -> DirectDecision {
        let decidedAt = now()
        switch state {
        case .awaitingConfirmation(let action, let deadline):
            // Direct input must fail closed at the deadline too, not only when
            // the countdown driver's tick() has already expired the action.
            if speechPausedAt == nil && decidedAt >= deadline {
                clearEarlyLatch()
                state = .cancelled(action, .timeout)
                return .ignored("expired")
            }
            if action.tier == .financial {
                // Fail closed: a missing prompt-completion timestamp must not
                // drop the read-back lock (a tap could otherwise confirm before
                // the amount was spoken).
                guard let promptAt = promptCompletedAt else { return .ignored("financial lock") }
                if decidedAt < promptAt.addingTimeInterval(Self.financialLock) {
                    return .ignored("financial lock")
                }
            }
            state = .arming(action, confirmedAt: decidedAt)
            return .accepted
        case .awaitingTurnComplete(let action):
            guard action.tier != .financial else {
                return .ignored("financial action requires the amount read-back")
            }
            earlyAffirmativeAt = decidedAt; earlyLatchSource = .direct
            return .latched
        case .arming:
            return .ignored("already confirmed; arm window in progress")
        case .idle, .confirmed, .cancelled:
            return .ignored("no pending action")
        }
    }
    /// On-screen card cancellation (direct input, not voice). Cancels any
    /// pending state with `.negation`; returns whether it cancelled.
    @discardableResult
    public func userCancelled() -> Bool {
        switch state {
        case .awaitingTurnComplete, .awaitingConfirmation, .arming:
            cancel(reason: .negation)
            return true
        default:
            return false
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
            clearEarlyLatch()
            state = .cancelled(action, reason)
        default:
            break
        }
    }
    private func abortReason(for id: UUID) -> CancelReason {
        if case .cancelled(let action, let reason) = state, action.id == id { return reason }
        return .superseded
    }
    /// Clears the latched early affirmative and its source marker together so
    /// they can never drift apart.
    private func clearEarlyLatch() {
        earlyAffirmativeAt = nil
        earlyLatchSource = nil
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
