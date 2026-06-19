import Foundation

public struct AdapterEvaluationCase: Equatable, Sendable {
    public let prompt: String
    public let expectedResponse: String

    public init(prompt: String, expectedResponse: String) {
        self.prompt = prompt
        self.expectedResponse = expectedResponse
    }
}

public struct AdapterEvaluationResult: Equatable, Sendable {
    public let testCase: AdapterEvaluationCase
    public let actualResponse: String
    public let matchesExpected: Bool
    public let responseTokenF1: Double
    public let expectedToolName: String?
    public let actualToolName: String?
    public let toolNameMatches: Bool?

    public init(
        testCase: AdapterEvaluationCase,
        actualResponse: String,
        matchesExpected: Bool,
        responseTokenF1: Double,
        expectedToolName: String?,
        actualToolName: String?,
        toolNameMatches: Bool?
    ) {
        self.testCase = testCase
        self.actualResponse = actualResponse
        self.matchesExpected = matchesExpected
        self.responseTokenF1 = responseTokenF1
        self.expectedToolName = expectedToolName
        self.actualToolName = actualToolName
        self.toolNameMatches = toolNameMatches
    }
}

public struct AdapterEvaluationSummary: Equatable, Sendable {
    public let total: Int
    public let matches: Int
    public let averageResponseTokenF1: Double
    public let toolSelectionTotal: Int
    public let toolSelectionMatches: Int

    public init(
        total: Int,
        matches: Int,
        averageResponseTokenF1: Double,
        toolSelectionTotal: Int,
        toolSelectionMatches: Int
    ) {
        self.total = total
        self.matches = matches
        self.averageResponseTokenF1 = averageResponseTokenF1
        self.toolSelectionTotal = toolSelectionTotal
        self.toolSelectionMatches = toolSelectionMatches
    }

    public var accuracy: Double {
        guard total > 0 else {
            return 0
        }
        return Double(matches) / Double(total)
    }

    public var toolSelectionAccuracy: Double {
        guard toolSelectionTotal > 0 else {
            return 0
        }
        return Double(toolSelectionMatches) / Double(toolSelectionTotal)
    }
}

public enum AdapterEvaluation {
    public static func cases(fromJSONL data: Data) throws -> [AdapterEvaluationCase] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ToolExecutionError.invalidArguments("Adapter eval data must be UTF-8 JSONL.")
        }

        return try text
            .split(separator: "\n")
            .enumerated()
            .map { index, line in
                let lineData = Data(line.utf8)
                let messages = try JSONDecoder().decode([AdapterTrainingMessage].self, from: lineData)
                guard let prompt = messages.first(where: { $0.role == "user" })?.content
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !prompt.isEmpty,
                    let expected = messages.last(where: { $0.role == "assistant" })?.content
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !expected.isEmpty else {
                    throw ToolExecutionError.invalidArguments("Invalid adapter eval JSONL line \(index + 1).")
                }
                return AdapterEvaluationCase(prompt: prompt, expectedResponse: expected)
            }
    }

    public static func score(_ results: [AdapterEvaluationResult]) -> AdapterEvaluationSummary {
        let toolResults = results.filter { $0.toolNameMatches != nil }
        return AdapterEvaluationSummary(
            total: results.count,
            matches: results.filter(\.matchesExpected).count,
            averageResponseTokenF1: results.isEmpty ? 0 : results.map(\.responseTokenF1).reduce(0, +) / Double(results.count),
            toolSelectionTotal: toolResults.count,
            toolSelectionMatches: toolResults.filter { $0.toolNameMatches == true }.count
        )
    }

    public static func result(for testCase: AdapterEvaluationCase, actualResponse: String) -> AdapterEvaluationResult {
        let expectedToolName = toolName(in: testCase.expectedResponse)
        let actualToolName = toolName(in: actualResponse)
        return AdapterEvaluationResult(
            testCase: testCase,
            actualResponse: actualResponse,
            matchesExpected: normalize(actualResponse) == normalize(testCase.expectedResponse),
            responseTokenF1: tokenF1(expected: testCase.expectedResponse, actual: actualResponse),
            expectedToolName: expectedToolName,
            actualToolName: actualToolName,
            toolNameMatches: expectedToolName.map { $0 == actualToolName }
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func tokenF1(expected: String, actual: String) -> Double {
        let expectedTokens = tokenCounts(in: expected)
        let actualTokens = tokenCounts(in: actual)
        let overlap = expectedTokens.reduce(0) { total, pair in
            total + min(pair.value, actualTokens[pair.key, default: 0])
        }
        let expectedCount = expectedTokens.values.reduce(0, +)
        let actualCount = actualTokens.values.reduce(0, +)
        guard expectedCount > 0, actualCount > 0, overlap > 0 else {
            return expectedCount == 0 && actualCount == 0 ? 1 : 0
        }
        let precision = Double(overlap) / Double(actualCount)
        let recall = Double(overlap) / Double(expectedCount)
        return 2 * precision * recall / (precision + recall)
    }

    private static func tokenCounts(in value: String) -> [String: Int] {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .reduce(into: [:]) { counts, token in
                counts[token, default: 0] += 1
            }
    }

    private static func toolName(in value: String) -> String? {
        let pattern = #""toolName"\s*:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[range])
    }
}
