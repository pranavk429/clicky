import Foundation
/// Test-only injectable clock. Lock-protected so the observed closures stay
/// safe while the test thread advances time between awaits.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 0)
    var now: Date {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
