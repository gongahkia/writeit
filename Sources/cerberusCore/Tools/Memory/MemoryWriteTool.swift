import Foundation
import FoundationModels

public struct MemoryWriteTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let content: String
        public let tags: [String]

        public init(content: String, tags: [String] = []) {
            self.content = content
            self.tags = tags
        }
    }

    public let name = "memory.write"
    public let capability = "Save a concise encrypted local memory record for future personalization."
    public let mutatesState = true
    public let argumentSchema = #"{"content":"memory to save","tags":["optional","tags"]}"#

    private let store: EncryptedMemoryStore

    public init(store: EncryptedMemoryStore = EncryptedMemoryStore()) {
        self.store = store
    }

    public func validate(_ arguments: Arguments) throws {
        guard !arguments.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("content is required")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let tags = arguments.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let record = MemoryRecord(content: arguments.content, tags: tags)
        try await store.append(record)

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "Saved memory.",
            metadata: ["id": record.id.uuidString]
        )
    }
}
