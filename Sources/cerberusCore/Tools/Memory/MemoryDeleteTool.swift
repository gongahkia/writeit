import Foundation
import FoundationModels

public struct MemoryDeleteTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let id: String?
        public let query: String?
        public let limit: Int

        public init(id: String? = nil, query: String? = nil, limit: Int = 1) {
            self.id = id
            self.query = query
            self.limit = limit
        }
    }

    public let name = "memory.delete"
    public let capability = "Forget encrypted local memory records by id or keyword query."
    public let mutatesState = true
    public let argumentSchema = #"{"id":"optional memory UUID","query":"optional keyword terms when id is unknown","limit":1}"#

    private let store: EncryptedMemoryStore

    public init(store: EncryptedMemoryStore = EncryptedMemoryStore()) {
        self.store = store
    }

    public func validate(_ arguments: Arguments) throws {
        let id = arguments.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let query = arguments.query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty || !query.isEmpty else {
            throw ToolExecutionError.invalidArguments("id or query is required")
        }
        if !id.isEmpty, UUID(uuidString: id) == nil {
            throw ToolExecutionError.invalidArguments("id must be a UUID")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        try validate(arguments)
        let ids: Set<UUID>
        if let rawID = arguments.id?.trimmingCharacters(in: .whitespacesAndNewlines), !rawID.isEmpty {
            ids = [UUID(uuidString: rawID)!]
        } else {
            let limit = ToolArgumentSupport.clampLimit(arguments.limit, default: 1, maximum: 10)
            let matches = try await store.search(query: arguments.query ?? "", limit: limit)
            ids = Set(matches.map(\.id))
        }

        let deletedCount = try await store.delete(ids: ids)
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: deletedCount == 1 ? "Forgot 1 memory." : "Forgot \(deletedCount) memories.",
            metadata: ["count": "\(deletedCount)"]
        )
    }
}
