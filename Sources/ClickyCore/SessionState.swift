import Foundation
/// Session lifecycle (spec §4.1 activation model: never always-listening —
/// a session starts via toggle, ends on toggle, kill switch, or idle timeout).
public enum SessionState: Equatable, Sendable {
    case idle, listening
    case reconnecting(reason: String)
    case stopped(reason: StopReason)
    public var isActive: Bool {
        switch self { case .listening, .reconnecting: return true; case .idle, .stopped: return false }
    }
}
public enum StopReason: String, Equatable, Sendable { case userToggle, idleTimeout, killSwitch, networkFailure }
public enum SessionTransition: Equatable, Sendable {
    case startRequested
    case stopRequested(StopReason)
    case connectionLost(reason: String)
    case connectionRestored
}
/// Pure state machine; all side effects (audio, socket, UI) hang off its output.
public struct SessionStateMachine {
    public private(set) var state: SessionState = .idle
    public init() {}
    @discardableResult
    public mutating func apply(_ transition: SessionTransition) -> SessionState {
        switch (state, transition) {
        case (.idle, .startRequested), (.stopped, .startRequested): state = .listening
        case (.listening, .stopRequested(let r)), (.reconnecting, .stopRequested(let r)): state = .stopped(reason: r)
        case (.listening, .connectionLost(let r)): state = .reconnecting(reason: r)
        case (.reconnecting, .connectionRestored): state = .listening
        default: break
        }
        return state
    }
}
