import Foundation

public struct AdapterTrainingMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct AdapterTrainingSample: Equatable, Sendable {
    public let messages: [AdapterTrainingMessage]

    public init(messages: [AdapterTrainingMessage]) {
        self.messages = messages
    }
}

public struct AdapterTrainingDatasetSplit: Equatable, Sendable {
    public let train: [AdapterTrainingSample]
    public let eval: [AdapterTrainingSample]

    public init(train: [AdapterTrainingSample], eval: [AdapterTrainingSample]) {
        self.train = train
        self.eval = eval
    }
}

public struct AdapterTrainingLengthStatistics: Codable, Equatable, Sendable {
    public let minimum: Int
    public let maximum: Int
    public let average: Double

    public init(values: [Int]) {
        minimum = values.min() ?? 0
        maximum = values.max() ?? 0
        average = values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
    }
}

public struct AdapterTrainingDatasetStatistics: Codable, Equatable, Sendable {
    public let totalSamples: Int
    public let taskCategories: [String: Int]
    public let tools: [String: Int]
    public let responseWords: AdapterTrainingLengthStatistics
    public let responseCharacters: AdapterTrainingLengthStatistics

    public init(records: [TranscriptRecord]) {
        totalSamples = records.count
        taskCategories = Self.counts(records.map(Self.taskCategory))
        tools = Self.counts(records.map(Self.toolName))
        responseWords = AdapterTrainingLengthStatistics(values: records.map { $0.response.split(whereSeparator: \.isWhitespace).count })
        responseCharacters = AdapterTrainingLengthStatistics(values: records.map { $0.response.count })
    }

    public var summaryLines: [String] {
        [
            "stats.samples: \(totalSamples)",
            "stats.taskCategories: \(Self.renderCounts(taskCategories))",
            "stats.tools: \(Self.renderCounts(tools))",
            String(format: "stats.responseWords: min=%d max=%d avg=%.2f", responseWords.minimum, responseWords.maximum, responseWords.average),
            String(format: "stats.responseCharacters: min=%d max=%d avg=%.2f", responseCharacters.minimum, responseCharacters.maximum, responseCharacters.average)
        ]
    }

    private static func taskCategory(for record: TranscriptRecord) -> String {
        guard let toolName = record.toolName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !toolName.isEmpty else {
            return "direct"
        }
        return toolName.split(separator: ".", maxSplits: 1).first.map(String.init) ?? toolName
    }

    private static func toolName(for record: TranscriptRecord) -> String {
        let toolName = record.toolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return toolName.isEmpty ? "none" : toolName
    }

    private static func counts(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { counts, value in
            counts[value, default: 0] += 1
        }
    }

    private static func renderCounts(_ counts: [String: Int]) -> String {
        counts.keys.sorted().map { "\($0)=\(counts[$0] ?? 0)" }.joined(separator: ", ")
    }
}

public struct AdapterTrainingDatasetExporter: Sendable {
    private let encoder: JSONEncoder

    public init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    public func samples(from records: [TranscriptRecord], limit: Int? = nil) -> [AdapterTrainingSample] {
        exportableRecords(from: records, limit: limit).compactMap(Self.sample)
    }

    public func statistics(from records: [TranscriptRecord], limit: Int? = nil) -> AdapterTrainingDatasetStatistics {
        AdapterTrainingDatasetStatistics(records: exportableRecords(from: records, limit: limit))
    }

    public func split(samples: [AdapterTrainingSample], evalFraction: Double = 0.2) throws -> AdapterTrainingDatasetSplit {
        guard !samples.isEmpty else {
            throw ToolExecutionError.invalidArguments("No transcript records are available for adapter dataset export.")
        }

        let boundedFraction = min(max(evalFraction, 0), 0.5)
        let evalCount = samples.count > 1 ? max(1, Int((Double(samples.count) * boundedFraction).rounded())) : 0
        let splitIndex = max(0, samples.count - evalCount)

        return AdapterTrainingDatasetSplit(
            train: Array(samples.prefix(splitIndex)),
            eval: Array(samples.suffix(evalCount))
        )
    }

    public func write(_ split: AdapterTrainingDatasetSplit, to directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try write(split.train, to: directoryURL.appendingPathComponent("train.jsonl"))
        try write(split.eval, to: directoryURL.appendingPathComponent("eval.jsonl"))
    }

    public func writeStatistics(_ statistics: AdapterTrainingDatasetStatistics, to directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let statsEncoder = JSONEncoder()
        statsEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try statsEncoder.encode(statistics)
        try data.write(to: directoryURL.appendingPathComponent("stats.json"), options: .atomic)
    }

    public static func defaultOutputDirectory() -> URL {
        CerberusDirectories.applicationSupportSubdirectory("adapter-dataset")
    }

    private func write(_ samples: [AdapterTrainingSample], to fileURL: URL) throws {
        let lines = try samples.map { sample in
            String(data: try encoder.encode(sample.messages), encoding: .utf8) ?? "[]"
        }
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func exportableRecords(from records: [TranscriptRecord], limit: Int? = nil) -> [TranscriptRecord] {
        let sortedRecords = records.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.timestamp < rhs.timestamp
        }
        let filtered = sortedRecords.filter { Self.sample(from: $0) != nil }
        guard let limit else {
            return filtered
        }
        return Array(filtered.suffix(max(0, limit)))
    }

    private static func sample(from record: TranscriptRecord) -> AdapterTrainingSample? {
        let request = record.request.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = record.response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !response.isEmpty else {
            return nil
        }

        return AdapterTrainingSample(messages: [
            AdapterTrainingMessage(role: "user", content: request),
            AdapterTrainingMessage(role: "assistant", content: response)
        ])
    }
}
