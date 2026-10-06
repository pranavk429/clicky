import Foundation

/// Dev key resolution for the demo builds. The Gemini key is read from the
/// process environment first (sourced-subshell launches), then from the local
/// key file `~/.clicky-gemini-key` (shell-style `GEMINI_API_KEY=…` lines).
/// Needed because `open build/Clicky.app` launches cannot carry environment
/// variables, and LaunchServices launches are required for correct TCC
/// attribution (speech/camera prompts must belong to Clicky itself).
///
/// The value is never logged, displayed, or written anywhere.
enum KeySource {
    static func geminiKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] {
            let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return keyFromFile()
    }

    private static func keyFromFile() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".clicky-gemini-key")
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for rawLine in contents.split(separator: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard line.hasPrefix("GEMINI_API_KEY=") else { continue }
            var value = String(line.dropFirst("GEMINI_API_KEY=".count))
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
