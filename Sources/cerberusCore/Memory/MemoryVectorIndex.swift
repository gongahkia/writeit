import Foundation

public enum MemoryVectorIndex {
    public static func ranked(records: [MemoryRecord], query: String, limit: Int) -> [MemoryRecord] {
        let queryVector = vector(for: query)
        guard !queryVector.isEmpty else {
            return records
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(limit)
                .map { $0 }
        }

        return records
            .compactMap { record -> (record: MemoryRecord, score: Double)? in
                let score = cosine(queryVector, vector(for: searchableText(record)))
                guard score > 0 else {
                    return nil
                }
                return (record, score)
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.record.timestamp > $1.record.timestamp
                }
                return $0.score > $1.score
            }
            .prefix(limit)
            .map(\.record)
    }

    static func vector(for text: String) -> [String: Double] {
        var counts: [String: Double] = [:]
        for token in tokens(in: text) {
            counts[token, default: 0] += 1
            let stem = stemmed(token)
            if stem != token {
                counts[stem, default: 0] += 0.5
            }
        }
        return counts
    }

    private static func searchableText(_ record: MemoryRecord) -> String {
        ([record.content, record.scope.rawValue] + record.tags).joined(separator: " ")
    }

    private static func tokens(in text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    private static func stemmed(_ token: String) -> String {
        if token.count > 4, token.hasSuffix("ing") {
            return String(token.dropLast(3))
        }
        if token.count > 3, token.hasSuffix("s") {
            return String(token.dropLast())
        }
        return token
    }

    private static func cosine(_ lhs: [String: Double], _ rhs: [String: Double]) -> Double {
        let dot = lhs.reduce(0) { partial, item in
            partial + item.value * (rhs[item.key] ?? 0)
        }
        guard dot > 0 else {
            return 0
        }
        let lhsMagnitude = sqrt(lhs.values.reduce(0) { $0 + ($1 * $1) })
        let rhsMagnitude = sqrt(rhs.values.reduce(0) { $0 + ($1 * $1) })
        guard lhsMagnitude > 0, rhsMagnitude > 0 else {
            return 0
        }
        return dot / (lhsMagnitude * rhsMagnitude)
    }
}
