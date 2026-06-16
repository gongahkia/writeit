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

public struct AdapterTrainingDatasetExporter: Sendable {
    private let encoder: JSONEncoder

    public init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    public func samples(from records: [TranscriptRecord], limit: Int? = nil) -> [AdapterTrainingSample] {
        let sortedRecords = records.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.timestamp < rhs.timestamp
        }

        let samples = sortedRecords.compactMap(Self.sample)
        guard let limit else {
            return samples
        }
        return Array(samples.suffix(max(0, limit)))
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

    public static func defaultOutputDirectory() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return baseURL
            .appendingPathComponent(CerberusCore.appName, isDirectory: true)
            .appendingPathComponent("adapter-dataset", isDirectory: true)
    }

    private func write(_ samples: [AdapterTrainingSample], to fileURL: URL) throws {
        let lines = try samples.map { sample in
            String(data: try encoder.encode(sample.messages), encoding: .utf8) ?? "[]"
        }
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
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
