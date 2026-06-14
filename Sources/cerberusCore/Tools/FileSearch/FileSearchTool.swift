import Foundation

public struct FileSearchTool: AssistantTool {
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
    public let capability = "Search indexed user files by filename using Spotlight metadata."
    public let mutatesState = false

    public init() {}

    public func validate(_ arguments: Arguments) throws {
        guard !arguments.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("query is required")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let limit = ToolArgumentSupport.clampLimit(arguments.limit)
        let results = await MetadataQueryRunner(
            queryText: arguments.query,
            scopePath: arguments.scopePath,
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
}

private struct FileSearchResult: Sendable {
    let path: String
    let modifiedDateISO8601: String?
}

@MainActor
private final class MetadataQueryRunner {
    private let queryText: String
    private let scopePath: String?
    private let limit: Int
    private var metadataQuery: NSMetadataQuery?
    private var observer: NSObjectProtocol?

    init(queryText: String, scopePath: String?, limit: Int) {
        self.queryText = queryText
        self.scopePath = scopePath
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

                    let results = self.collectResults(from: query)
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
        guard let scopePath, !scopePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [NSMetadataQueryUserHomeScope]
        }

        return [URL(fileURLWithPath: scopePath)]
    }

    private func collectResults(from query: NSMetadataQuery) -> [FileSearchResult] {
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
