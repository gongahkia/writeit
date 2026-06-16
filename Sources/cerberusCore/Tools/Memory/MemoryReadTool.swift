import Foundation
import FoundationModels

public struct MemoryReadTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let query: String
        public let limit: Int

        public init(query: String = "", limit: Int = 5) {
            self.query = query
            self.limit = limit
        }
    }

    public let name = "memory.read"
    public let capability = "Read encrypted local memory records by keyword."
    public let mutatesState = false
    public let argumentSchema = #"{"query":"optional keyword terms","limit":5}"#

    private let store: EncryptedMemoryStore

    public init(store: EncryptedMemoryStore = EncryptedMemoryStore()) {
        self.store = store
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let limit = ToolArgumentSupport.clampLimit(arguments.limit, default: 5, maximum: 20)
        let records = try await store.search(query: arguments.query, limit: limit)
        let payload = records
            .map(formatRecord)
            .joined(separator: "\n")

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: records.count == 1 ? "Found 1 memory." : "Found \(records.count) memories.",
            untrustedPayload: payload,
            metadata: ["count": "\(records.count)"]
        )
    }

    private func formatRecord(_ record: MemoryRecord) -> String {
        let timestamp = ISO8601DateFormatter().string(from: record.timestamp)
        let tagText = record.tags.isEmpty ? "" : " [\(record.tags.joined(separator: ", "))]"
        return "- \(timestamp)\(tagText): \(record.content)"
    }
}
