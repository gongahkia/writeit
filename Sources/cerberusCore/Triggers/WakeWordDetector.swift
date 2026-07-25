import Foundation

public struct WakeWordDetector: Sendable {
    public let phrases: [String]

    public init(phrases: [String] = ["hey cerberus"]) {
        self.phrases = phrases
            .map(Self.normalize)
            .filter { !$0.isEmpty }
    }

    public func detectsWakeWord(in text: String) -> Bool {
        guard !phrases.isEmpty else {
            return false
        }

        let normalizedText = Self.normalize(text)
        return phrases.contains { phrase in
            normalizedText.contains(phrase)
        }
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
