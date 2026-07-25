import Foundation

public enum VoiceConfirmationDecision: Equatable, Sendable {
    case accept
    case deny
}

public enum VoiceConfirmationParser {
    public static func decision(in text: String) -> VoiceConfirmationDecision? {
        let normalized = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else {
            return nil
        }

        let words = Set(normalized)
        if words.contains(where: denyWords.contains) {
            return .deny
        }
        if words.contains(where: acceptWords.contains) || containsPhrase(["do", "it"], in: normalized) {
            return .accept
        }
        return nil
    }

    private static let acceptWords: Set<String> = [
        "accept",
        "approve",
        "confirm",
        "go",
        "proceed",
        "sure",
        "yes",
        "yeah",
        "yep"
    ]

    private static let denyWords: Set<String> = [
        "cancel",
        "deny",
        "no",
        "nope",
        "stop"
    ]

    private static func containsPhrase(_ phrase: [String], in words: [String]) -> Bool {
        guard words.count >= phrase.count else {
            return false
        }

        return words.indices.contains { index in
            let endIndex = index + phrase.count
            guard endIndex <= words.endIndex else {
                return false
            }
            return Array(words[index..<endIndex]) == phrase
        }
    }
}
