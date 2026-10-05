import Foundation

/// Backoff + goAway timing rules for session recovery (spec §4.1; Validation 01 S5:
/// reconnect target ≤2 s). All delays flow through `SleepProviding`, so tests run
/// with an injected clock.
public struct ReconnectPolicy: Sendable {
    public static let maxResumeAttempts = 3
    public static let baseDelaySeconds: TimeInterval = 0.5
    public static let maxDelaySeconds: TimeInterval = 4

    /// The goAway margin doubles as the reconnect target budget: reconnect starts
    /// `goAwayMarginSeconds` before `timeLeft` expires (Validation 01 S5: ≤2 s).
    public static let goAwayMarginSeconds: TimeInterval = 2

    public static func backoffDelay(attempt: Int) -> TimeInterval {
        min(baseDelaySeconds * pow(2, Double(max(0, attempt - 1))), maxDelaySeconds)
    }

    public static func goAwayDelay(timeLeftSeconds: Double?) -> TimeInterval {
        guard let timeLeftSeconds else { return 0 }
        return max(0, timeLeftSeconds - goAwayMarginSeconds)
    }
}

public protocol SleepProviding: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

public struct RealSleeper: SleepProviding {
    public init() {}
    public func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

/// Returns immediately — mock replay and reconnect tests stay deterministic.
public struct ImmediateSleeper: SleepProviding {
    public init() {}
    public func sleep(seconds: TimeInterval) async throws {}
}
