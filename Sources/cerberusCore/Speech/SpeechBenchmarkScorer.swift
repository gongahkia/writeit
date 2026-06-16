import Foundation

public enum SpeechBenchmarkScorer {
    public static func normalizedWords(_ text: String) -> [String] {
        let scalars = text.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        return String(scalars)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    public static func wordErrorRate(expected: String, actual: String) -> Double {
        let expectedWords = normalizedWords(expected)
        let actualWords = normalizedWords(actual)
        guard !expectedWords.isEmpty else {
            return actualWords.isEmpty ? 0 : 1
        }
        return Double(editDistance(expectedWords, actualWords)) / Double(expectedWords.count)
    }

    private static func editDistance(_ lhs: [String], _ rhs: [String]) -> Int {
        var previous = Array(0...rhs.count)
        for (leftIndex, leftWord) in lhs.enumerated() {
            var current = [leftIndex + 1] + Array(repeating: 0, count: rhs.count)
            for (rightIndex, rightWord) in rhs.enumerated() {
                if leftWord == rightWord {
                    current[rightIndex + 1] = previous[rightIndex]
                } else {
                    current[rightIndex + 1] = min(
                        previous[rightIndex],
                        previous[rightIndex + 1],
                        current[rightIndex]
                    ) + 1
                }
            }
            previous = current
        }
        return previous[rhs.count]
    }
}
