import Foundation

public enum LocalTelemetryCategory: String, Codable, Equatable, Sendable {
    case planning
    case toolExecution = "tool_execution"
}

public struct LocalTelemetryRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let category: LocalTelemetryCategory
    public let name: String
    public let durationSeconds: Double
    public let succeeded: Bool
    public let qualitySignal: String
    public let modelProfile: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: LocalTelemetryCategory,
        name: String,
        durationSeconds: Double,
        succeeded: Bool,
        qualitySignal: String,
        modelProfile: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.name = name
        self.durationSeconds = durationSeconds
        self.succeeded = succeeded
        self.qualitySignal = qualitySignal
        self.modelProfile = modelProfile
    }
}

public actor LocalTelemetryStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL = LocalTelemetryStore.defaultFileURL()) {
        self.fileURL = fileURL
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
    }

    public func append(_ record: LocalTelemetryRecord) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let line = try encoder.encode(record)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n".utf8))
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            try line.write(to: fileURL, options: .atomic)
        }
    }

    public func records() throws -> [LocalTelemetryRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return []
        }

        return try text
            .split(separator: "\n")
            .map { try decoder.decode(LocalTelemetryRecord.self, from: Data($0.utf8)) }
    }

    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }

    public static func defaultFileURL() -> URL {
        CerberusDirectories.applicationSupportFile("telemetry.jsonl")
    }
}
