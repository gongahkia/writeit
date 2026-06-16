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

    public init(testCase: AdapterEvaluationCase, actualResponse: String, matchesExpected: Bool) {
        self.testCase = testCase
        self.actualResponse = actualResponse
        self.matchesExpected = matchesExpected
    }
}

public struct AdapterEvaluationSummary: Equatable, Sendable {
    public let total: Int
    public let matches: Int

    public init(total: Int, matches: Int) {
        self.total = total
        self.matches = matches
    }

    public var accuracy: Double {
        guard total > 0 else {
            return 0
        }
        return Double(matches) / Double(total)
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
        AdapterEvaluationSummary(
            total: results.count,
            matches: results.filter(\.matchesExpected).count
        )
    }

    public static func result(for testCase: AdapterEvaluationCase, actualResponse: String) -> AdapterEvaluationResult {
        AdapterEvaluationResult(
            testCase: testCase,
            actualResponse: actualResponse,
            matchesExpected: normalize(actualResponse) == normalize(testCase.expectedResponse)
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
