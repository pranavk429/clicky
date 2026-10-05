import Foundation
import Combine
import ClickyCore
extension Notification.Name { static let clickySessionStateChanged = Notification.Name("clickySessionStateChanged") }
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published private(set) var session: SessionState = .idle
    private var machine = SessionStateMachine()
    private init() {}
    func toggleSession() {
        switch machine.state {
        case .idle, .stopped: transition(.startRequested)
        case .listening, .reconnecting: transition(.stopRequested(.userToggle))
        }
    }
    func transition(_ transition: SessionTransition) {
        session = machine.apply(transition)
        NotificationCenter.default.post(name: .clickySessionStateChanged, object: session)
    }
}
