import Foundation

/// What the model asked for: free text from the voice channel plus an optional
/// role hint from the tool call. Scoring is local and deterministic — the model
/// names a target, it never picks one (spec §4.4 authority rule).
public struct ElementQuery: Equatable, Sendable {
    public let text: String
    public let role: String?
    public init(text: String, role: String? = nil) {
        self.text = text
        self.role = role
    }
}

public struct ScoredElement: Sendable {
    public let snapshot: ElementSnapshot
    public let score: Double
}

public enum ElementMatcher {
    /// Best match, or nil when nothing clears 0 (e.g. only secure fields matched).
    public static func bestMatch(for query: ElementQuery, in candidates: [ElementSnapshot]) -> ScoredElement? {
        ranked(candidates, for: query).first
    }
    /// Descending score (Swift's sort is not stable; two equal-score targets are interchangeable).
    public static func ranked(_ candidates: [ElementSnapshot], for query: ElementQuery) -> [ScoredElement] {
        candidates
            .map { ScoredElement(snapshot: $0, score: score(query: query, candidate: $0)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
    }
    /// Exact 1.0 · contains 0.6 · token Jaccard × 0.4 (threshold 0.5).
    /// Matches title, description, or `kAXValueAttribute` text (search bars and
    /// text fields store their content in the value, not the title).
    /// Role hint: ×1.2 on match, ×0.5 on mismatch. Disabled ×0.5.
    /// Secure fields always 0 — credentials are Tier-5 territory, never a target.
    public static func score(query: ElementQuery, candidate: ElementSnapshot) -> Double {
        guard !candidate.isSecureField else { return 0 }
        let wanted = normalize(query.text)
        guard !wanted.isEmpty else { return 0 }
        var score = max(similarity(wanted, candidate.key.title),
                        similarity(wanted, candidate.key.description),
                        similarity(wanted, candidate.value))
        guard score > 0 else { return 0 }
        if let role = query.role {
            score *= normalize(role) == candidate.key.role ? 1.2 : 0.5
        }
        if !candidate.isEnabled { score *= 0.5 }
        return score
    }
    static func similarity(_ query: String, _ candidate: String) -> Double {
        guard !candidate.isEmpty else { return 0 }
        if query == candidate { return 1.0 }
        if query.contains(candidate) || candidate.contains(query) { return 0.6 }
        let queryTokens = tokens(query)
        let candidateTokens = tokens(candidate)
        guard !queryTokens.isEmpty, !candidateTokens.isEmpty else { return 0 }
        let overlap = Double(queryTokens.intersection(candidateTokens).count)
            / Double(queryTokens.union(candidateTokens).count)
        return overlap >= 0.5 ? 0.4 * overlap : 0
    }
    static func tokens(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    }
    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
