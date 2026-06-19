import Foundation
import FoundationModels

public struct MemoryWriteTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let content: String
        public let tags: [String]
        public let scope: String?

        public init(content: String, tags: [String] = [], scope: String? = nil) {
            self.content = content
            self.tags = tags
            self.scope = scope
        }
    }

    public let name = "memory.write"
    public let capability = "Save a concise encrypted local memory record scoped as a personal preference, project fact, or temporary session fact."
    public let mutatesState = true
    public let argumentSchema = #"{"content":"memory to save","tags":["optional","tags"],"scope":"personal_preference|project_fact|temporary_session_fact"}"#

    private let store: EncryptedMemoryStore

    public init(store: EncryptedMemoryStore = EncryptedMemoryStore()) {
        self.store = store
    }

    public func validate(_ arguments: Arguments) throws {
        guard !arguments.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("content is required")
        }
        if let scope = arguments.scope,
           MemoryScope(rawValue: scope.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
            throw ToolExecutionError.invalidArguments("scope must be personal_preference, project_fact, or temporary_session_fact")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        try validate(arguments)
        let tags = arguments.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let scope = arguments.scope
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap(MemoryScope.init(rawValue:)) ?? .personalPreference
        let record = MemoryRecord(content: arguments.content, tags: tags, scope: scope)
        try await store.append(record)

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "Saved memory.",
            metadata: ["id": record.id.uuidString, "scope": record.scope.rawValue]
        )
    }
}
