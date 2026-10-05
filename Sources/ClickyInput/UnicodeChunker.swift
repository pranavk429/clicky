import Foundation
/// `keyboardSetUnicodeString` processes ≤20 UTF-16 units per event (errata B7).
/// Chunk without ever splitting a grapheme cluster (surrogate pairs, ZWJ
/// sequences, Devanagari conjuncts).
public enum UnicodeChunker {
    public static let maxUTF16UnitsPerEvent = 20
    public static func chunk(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        var currentUnits = 0
        for character in text {
            let units = character.utf16.count
            if units > maxUTF16UnitsPerEvent {           // oversized single cluster: emit alone
                if !current.isEmpty { chunks.append(current); current = ""; currentUnits = 0 }
                chunks.append(String(character))
                continue
            }
            if currentUnits + units > maxUTF16UnitsPerEvent {
                chunks.append(current); current = ""; currentUnits = 0
            }
            current.append(character); currentUnits += units
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
