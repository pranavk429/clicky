import Foundation
/// Local number parsing for Tier 4 confirmations (spec §4.4; errata C3):
/// "₹500" / "paanch sau" / "५००" must all normalize to the same value here,
/// on-device. The model never judges money.
public enum AmountNormalizer {
    public static func matches(expected: Decimal, in transcript: String) -> Bool {
        extractAmounts(from: transcript).contains(expected)
    }
    public static func normalize(_ phrase: String) -> Decimal? { extractAmounts(from: phrase).first }
    public static func extractAmounts(from text: String) -> [Decimal] {
        let tokens = tokenize(text)
        var amounts: [Decimal] = []
        var index = 0
        while index < tokens.count {
            if let numeric = decimalToken(tokens[index]) {
                amounts.append(numeric); index += 1
            } else if let first = wordValue(tokens[index]) {
                var compound = 0
                var current = first
                var cursor = index + 1
                while cursor < tokens.count {
                    if let multiplier = multipliers[tokens[cursor]] {
                        compound += max(current, 1) * multiplier; current = 0
                    } else if let value = wordValue(tokens[cursor]) {
                        compound += current; current = value
                    } else {
                        break
                    }
                    cursor += 1
                }
                amounts.append(Decimal(compound + current)); index = cursor
            } else if let multiplier = multipliers[tokens[index]] {
                amounts.append(Decimal(multiplier)); index += 1
            } else {
                index += 1
            }
        }
        return amounts
    }
    private static func tokenize(_ text: String) -> [String] {
        var mapped = ""
        for character in text { mapped.append(devanagariDigits[character] ?? character) }
        return SafetyText.normalized(mapped)
            .replacingOccurrences(of: "₹", with: " ")
            .replacingOccurrences(of: "rs.", with: " ")
            .replacingOccurrences(of: "रु.", with: " ")
            .replacingOccurrences(of: ",", with: "")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." })
            .map(String.init)
    }
    private static func wordValue(_ token: String) -> Int? { unitValues[token] ?? tensValues[token] }
    private static func decimalToken(_ token: String) -> Decimal? {
        var digits = ""
        var seenDot = false
        for character in token {
            if character.isNumber && character.isASCII {
                digits.append(character)
            } else if character == "." && !seenDot && !digits.isEmpty {
                seenDot = true; digits.append(character)
            } else {
                return nil
            }
        }
        while digits.hasSuffix(".") { digits.removeLast() }
        guard !digits.isEmpty else { return nil }
        return Decimal(string: digits)
    }
    private static let devanagariDigits: [Character: Character] = [
        "०": "0", "१": "1", "२": "2", "३": "3", "४": "4",
        "५": "5", "६": "6", "७": "7", "८": "8", "९": "9",
    ]
    private static let unitValues: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "एक": 1, "दो": 2, "दोन": 2, "तीन": 3, "चार": 4, "पाँच": 5, "पांच": 5, "पाच": 5,
        "सहा": 6, "छह": 6, "छः": 6, "सात": 7, "आठ": 8, "नौ": 9, "नऊ": 9, "दस": 10, "दहा": 10,
        "ek": 1, "do": 2, "teen": 3, "char": 4, "chaar": 4, "paanch": 5, "panch": 5, "paach": 5,
        "che": 6, "saat": 7, "aath": 8, "nau": 9, "das": 10, "dus": 10,
    ]
    private static let tensValues: [String: Int] = [
        "बीस": 20, "तीस": 30, "चालीस": 40, "पचास": 50, "साठ": 60, "सत्तर": 70, "अस्सी": 80, "नब्बे": 90,
        "वीस": 20, "चाळीस": 40, "पन्नास": 50, "ऐंशी": 80, "नव्वद": 90,
        "दोनशे": 200, "तीनशे": 300, "चारशे": 400, "पाचशे": 500, "सहाशे": 600, "सातशे": 700, "आठशे": 800, "नऊशे": 900,
        "bees": 20, "tees": 30, "chalis": 40, "pachas": 50, "pannas": 50,
        "saath": 60, "sattar": 70, "assi": 80, "nabbe": 90,
    ]
    private static let multipliers: [String: Int] = [
        "सौ": 100, "शंभर": 100, "शे": 100, "हज़ार": 1000, "हजार": 1000, "लाख": 100000,
        "sau": 100, "hazaar": 1000, "hazar": 1000, "hajar": 1000, "thousand": 1000,
        "hundred": 100, "lakh": 100000, "lac": 100000,
    ]
}
