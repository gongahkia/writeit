import Foundation
import FoundationModels

public struct FileSearchTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let query: String
        public let scopePath: String?
        public let limit: Int

        public init(query: String, scopePath: String? = nil, limit: Int = 10) {
            self.query = query
            self.scopePath = scopePath
            self.limit = limit
        }
    }

    public let name = "files.search"
    public let capability = "Search indexed user files by filename using Spotlight metadata within approved folders."
    public let mutatesState = false
    public let argumentSchema = #"{"query":"filename terms","scopePath":"optional approved folder/subfolder path; omit to search all approved folders","limit":10}"#

    private let approvedScopePathsProvider: @Sendable () -> [String]?

    public init(approvedScopePaths: [String]? = []) {
        approvedScopePathsProvider = { approvedScopePaths }
    }

    public init(approvedScopePathsProvider: @escaping @Sendable () -> [String]?) {
        self.approvedScopePathsProvider = approvedScopePathsProvider
    }

    public func validate(_ arguments: Arguments) throws {
        guard !arguments.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("query is required")
        }

        _ = try validatedScopePaths(arguments.scopePath)
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let limit = ToolArgumentSupport.clampLimit(arguments.limit)
        let scopePaths = try validatedScopePaths(arguments.scopePath)
        let results = await MetadataQueryRunner(
            queryText: arguments.query,
            scopePaths: scopePaths,
            limit: limit
        ).run()

        let payload = results
            .map { "- \($0.path) [\($0.modifiedDateISO8601 ?? "unknown modified date")]" }
            .joined(separator: "\n")

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: results.count == 1 ? "Found 1 file." : "Found \(results.count) files.",
            untrustedPayload: payload,
            metadata: ["count": "\(results.count)"]
        )
    }

    private func validatedScopePaths(_ path: String?) throws -> [String]? {
        let approvedScopePaths = try normalizedApprovedScopePaths()
        let trimmedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard let approvedScopePaths else {
            guard !trimmedPath.isEmpty else {
                return nil
            }
            return [try FileSearchScopeStore.normalizedDirectoryInHome(trimmedPath)]
        }

        guard !approvedScopePaths.isEmpty else {
            throw ToolExecutionError.denied("Add a file search folder in Settings before using files.search.")
        }

        guard !trimmedPath.isEmpty else {
            return approvedScopePaths
        }

        let scopePath = try FileSearchScopeStore.normalizedDirectoryInHome(trimmedPath)
        guard approvedScopePaths.contains(where: { FileSearchScopeStore.contains(scopePath, in: $0) }) else {
            throw ToolExecutionError.denied("File search scope must be inside an approved folder.")
        }
        return [scopePath]
    }

    private func normalizedApprovedScopePaths() throws -> [String]? {
        guard let paths = approvedScopePathsProvider() else {
            return nil
        }

        var seen = Set<String>()
        return try paths
            .map(FileSearchScopeStore.normalizedDirectoryInHome)
            .filter { seen.insert($0).inserted }
            .sorted()
    }
}

private struct FileSearchResult: Sendable {
    let path: String
    let modifiedDateISO8601: String?
}

@MainActor
private final class MetadataQueryRunner {
    private let queryText: String
    private let scopePaths: [String]?
    private let limit: Int
    private var metadataQuery: NSMetadataQuery?
    private var observer: (any NSObjectProtocol)?

    init(queryText: String, scopePaths: [String]?, limit: Int) {
        self.queryText = queryText
        self.scopePaths = scopePaths
        self.limit = limit
    }

    func run() async -> [FileSearchResult] {
        await withCheckedContinuation { continuation in
            let query = NSMetadataQuery()
            metadataQuery = query
            query.searchScopes = searchScopes()
            query.predicate = NSPredicate(
                format: "%K CONTAINS[cd] %@",
                NSMetadataItemFSNameKey,
                queryText
            )

            observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else {
                        continuation.resume(returning: [])
                        return
                    }

                    let results = self.collectResults()
                    self.stop()
                    continuation.resume(returning: results)
                }
            }

            if !query.start() {
                continuation.resume(returning: [])
                stop()
            }
        }
    }

    private func searchScopes() -> [Any] {
        guard let scopePaths, !scopePaths.isEmpty else {
            return [NSMetadataQueryUserHomeScope]
        }

        return scopePaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func collectResults() -> [FileSearchResult] {
        guard let query = metadataQuery else {
            return []
        }

        query.disableUpdates()

        return query.results
            .compactMap { $0 as? NSMetadataItem }
            .prefix(limit)
            .compactMap { item in
                guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else {
                    return nil
                }

                let modifiedDate = item.value(forAttribute: NSMetadataItemContentModificationDateKey) as? Date
                return FileSearchResult(
                    path: path,
                    modifiedDateISO8601: modifiedDate.map { ISO8601DateFormatter().string(from: $0) }
                )
            }
    }

    private func stop() {
        metadataQuery?.stop()
        metadataQuery = nil

        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }
}
