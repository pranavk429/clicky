import Foundation
/// Provenance check for tool calls (spec §4.4 injection containment; errata
/// C5). Only text heard on the user's command channel (voice or the text
/// command box) can create intents — screen content never can. A call is
/// authorized when every token of one of its anchors appears in a recorded
/// intent inside the window, or when a quorum of the anchor's meaningful
/// (non-filler, non-command) tokens does — the model's `intent` is a live
/// paraphrase, not always a verbatim quote (demo fix, 2026-10-06).
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
    public init(windowSeconds: TimeInterval = 120, capacity: Int = 20, now: @Sendable @escaping () -> Date = { Date() }) {
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
            for phrase in phrases {
                if SafetyText.allTokensPresent(phrase, in: intent.text)
                    || paraphraseOverlapMatches(phrase, in: intent.text) {
                    return .authorized(intentID: intent.id)
                }
            }
        }
        return .refused(.noMatchingIntent)
    }
    /// Relaxed trace for the model's paraphrased `intent` strings: at least
    /// half of the anchor's meaningful tokens must appear in one recorded
    /// utterance. Zero meaningful overlap (including a verb-only match against
    /// an unspoken target) is still refused, preserving T10.
    private func paraphraseOverlapMatches(_ phrase: String, in text: String) -> Bool {
        let content = SafetyText.tokens(of: phrase).filter { !Self.weakTokens.contains($0) }
        guard !content.isEmpty else { return false }
        let spoken = Set(SafetyText.tokens(of: text))
        let matched = content.filter { token in
            spoken.contains(token)
                || spoken.contains(where: { Self.morphologicalMatch(token, $0) })
        }
        return !matched.isEmpty && matched.count * 2 >= content.count
    }
    /// Token equality plus prefix tolerance for plurals/inflections
    /// ("notes" ↔ "note", "खोलो" ↔ "खोल"); short prefixes are not trusted.
    private static func morphologicalMatch(_ anchor: String, _ spoken: String) -> Bool {
        guard min(anchor.count, spoken.count) >= 3 else { return false }
        return anchor.hasPrefix(spoken) || spoken.hasPrefix(anchor)
    }
    /// Function words, politeness, and command-frame verbs carry no target
    /// meaning: a paraphrase may drop, add, or swap them. Generic weak words
    /// cannot authorize alone, so an anchor like "open Terminal" cannot be
    /// traced by "open" when the user never said "Terminal".
    private static let weakTokens: Set<String> = [
        "a", "an", "the", "this", "that", "these", "those", "my", "your", "his", "her",
        "our", "their", "its", "it", "is", "are", "was", "were", "be", "been", "am",
        "do", "does", "did", "to", "of", "in", "on", "at", "for", "with", "from",
        "by", "as", "and", "or", "but", "if", "then", "than", "so", "please", "kindly",
        "hey", "ok", "okay", "just", "now", "here", "there", "up", "down", "out",
        "over", "under", "again", "all", "any", "some", "can", "could", "would",
        "should", "will", "shall", "may", "might", "must", "i", "you", "he", "she",
        "we", "they", "me", "him", "us", "them", "about", "into", "off", "very",
        "really", "maybe", "let", "lets", "want", "wants", "need", "needs", "help",
        "open", "close", "click", "press", "tap", "select", "choose", "pick", "delete",
        "remove", "trash", "type", "write", "read", "copy", "cut", "paste", "move",
        "drag", "drop", "scroll", "switch", "launch", "start", "run", "save", "send",
        "search", "find", "show", "hide", "take", "get", "put", "set", "change",
        "turn", "make", "create", "add", "edit", "rename", "download", "upload",
        "pay", "buy", "call", "play", "stop", "pause", "resume", "undo", "redo",
        "confirm", "cancel", "accept", "reject", "quit", "exit", "visit", "browse",
        "navigate", "focus", "activate", "use", "try", "check", "look", "see",
        "tell", "give", "bring", "go",
        "का", "की", "के", "को", "में", "पर", "से", "और", "या", "है", "हैं", "हो",
        "करो", "कर", "करें", "दो", "दीजिए", "कृपया", "मेरा", "मेरी", "मेरे", "यह",
        "वह", "इस", "उस", "जरा", "अब", "यहाँ", "वहाँ", "ऊपर", "नीचे", "अंदर", "बाहर",
        "खोलो", "खोल", "बंद", "हटाओ", "हटा", "मिटाओ", "लिखो", "लिख", "पढ़ो", "पढ़",
        "दबाओ", "क्लिक"
    ]
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
