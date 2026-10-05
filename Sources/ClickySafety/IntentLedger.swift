import Foundation
/// Provenance check for tool calls (spec §4.4 injection containment; errata
/// C5). Only text heard on the user's command channel (voice or the text
/// command box) can create intents — screen content never can. A call is
/// authorized only when every token of one of its anchors appears in a
/// recorded intent inside the window.
public actor IntentLedger {
    public struct Intent: Equatable, Sendable {
        public let id: UUID
        public let text: String
        public let source: Source
        public let issuedAt: Date
        public enum Source: String, Equatable, Sendable { case voice, textCommand }
    }
    public struct ToolCallIntent: Equatable, Sendable {
        public let toolName: String
        /// Short target descriptions (element title, app name, domain). Do not
        /// pass full URLs; hosts are extracted automatically.
        public let anchors: [String]
        public init(toolName: String, anchors: [String]) { self.toolName = toolName; self.anchors = anchors }
    }
    public enum Refusal: Equatable, Sendable { case noAnchors, noMatchingIntent }
    public enum Decision: Equatable, Sendable {
        case authorized(intentID: UUID)
        case refused(Refusal)
    }
    private let window: TimeInterval
    private let capacity: Int
    private let now: @Sendable () -> Date
    private var intents: [Intent] = []
    public init(windowSeconds: TimeInterval = 120, capacity: Int = 20, now: @Sendable @escaping () -> Date = Date.init) {
        self.window = windowSeconds; self.capacity = capacity; self.now = now
    }
    @discardableResult
    public func record(_ text: String, source: Intent.Source = .voice) -> Intent? {
        guard !SafetyText.tokens(of: text).isEmpty else { return nil }
        let intent = Intent(id: UUID(), text: SafetyText.normalized(text), source: source, issuedAt: now())
        intents.append(intent); prune()
        return intent
    }
    public func authorize(_ call: ToolCallIntent) -> Decision {
        prune()
        let phrases = call.anchors.compactMap(anchorPhrase)
        guard !phrases.isEmpty else { return .refused(.noAnchors) }
        for intent in intents.reversed() {
            for phrase in phrases where SafetyText.allTokensPresent(phrase, in: intent.text) {
                return .authorized(intentID: intent.id)
            }
        }
        return .refused(.noMatchingIntent)
    }
    private func anchorPhrase(_ anchor: String) -> String? {
        let trimmed = anchor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return trimmed
    }
    private func prune() {
        let cutoff = now().addingTimeInterval(-window)
        intents.removeAll { $0.issuedAt < cutoff }
        if intents.count > capacity { intents.removeFirst(intents.count - capacity) }
    }
}
