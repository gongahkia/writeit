import CoreGraphics
import Foundation
import FoundationModels

public struct ScreenSnapshotTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let scope: String?

        public init(scope: String? = nil) {
            self.scope = scope
        }
    }

    public let name = "screen.snapshot"
    public let capability = "Capture the main display or active window to a local PNG file for user-visible screen context."
    public let mutatesState = false
    public let argumentSchema = #"{"scope":"main_display|active_window"}"#

    private let outputDirectoryURL: URL
    private let cachePolicy: ScreenSnapshotCachePolicy
    private let hasScreenCaptureAccess: @Sendable () -> Bool

    public init(
        outputDirectoryURL: URL = ScreenSnapshotTool.defaultOutputDirectoryURL(),
        cachePolicy: ScreenSnapshotCachePolicy = .default,
        hasScreenCaptureAccess: @escaping @Sendable () -> Bool = CGPreflightScreenCaptureAccess
    ) {
        self.outputDirectoryURL = outputDirectoryURL
        self.cachePolicy = cachePolicy
        self.hasScreenCaptureAccess = hasScreenCaptureAccess
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        guard hasScreenCaptureAccess() else {
            throw ToolExecutionError.denied("Screen Recording access is not granted.")
        }

        let requestedScope = try ScreenCaptureScope.parse(arguments.scope)
        let capture = try await ScreenCaptureSupport.captureImage(scope: requestedScope)
        let image = capture.image
        let fileURL = outputDirectoryURL
            .appendingPathComponent(Self.fileName(for: Date()), isDirectory: false)
        try ScreenCaptureSupport.writePNG(image, to: fileURL)
        try ScreenSnapshotCache.cleanDirectory(outputDirectoryURL, preserving: fileURL, policy: cachePolicy)
        let imageSize = CGSize(width: image.width, height: image.height)

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "Captured \(capture.scope.spokenDescription).",
            untrustedPayload: Self.payload(
                fileURL: fileURL,
                imageSize: imageSize,
                scope: capture.scope,
                sourceDescription: capture.sourceDescription
            ),
            metadata: [
                "imagePath": fileURL.path,
                "imageWidth": "\(image.width)",
                "imageHeight": "\(image.height)",
                "scope": capture.scope.rawValue
            ]
        )
    }

    static func payload(
        fileURL: URL,
        imageSize: CGSize,
        scope: ScreenCaptureScope = .mainDisplay,
        sourceDescription: String = "main display"
    ) -> String {
        """
        Screen snapshot saved.
        file: \(fileURL.path)
        scope: \(scope.rawValue)
        source: \(sourceDescription)
        image: \(Int(imageSize.width))x\(Int(imageSize.height))
        Use screen.ocr when the model needs screen text because this macOS FoundationModels SDK exposes text prompts only.
        """
    }

    public static func defaultOutputDirectoryURL() -> URL {
        CerberusDirectories.cacheSubdirectory("screen-snapshots")
    }

    private static func fileName(for date: Date) -> String {
        "screen-\(Int(date.timeIntervalSince1970))-\(UUID().uuidString).png"
    }
}

public struct ScreenSnapshotCachePolicy: Sendable {
    public static let `default` = ScreenSnapshotCachePolicy(maximumFileCount: 50, maximumAge: 7 * 24 * 60 * 60)

    public let maximumFileCount: Int
    public let maximumAge: TimeInterval
    public let now: @Sendable () -> Date

    public init(
        maximumFileCount: Int,
        maximumAge: TimeInterval,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.maximumFileCount = max(1, maximumFileCount)
        self.maximumAge = max(0, maximumAge)
        self.now = now
    }
}

public enum ScreenSnapshotCache {
    public static func latestSnapshotURL(in directoryURL: URL) -> URL? {
        (try? snapshotFiles(in: directoryURL).first)?.url
    }

    public static func snapshotCount(in directoryURL: URL) -> Int {
        (try? snapshotFiles(in: directoryURL).count) ?? 0
    }

    @discardableResult
    public static func deleteSnapshots(in directoryURL: URL) throws -> Int {
        let snapshots = try snapshotFiles(in: directoryURL)
        for snapshot in snapshots {
            try FileManager.default.removeItem(at: snapshot.url)
        }
        return snapshots.count
    }

    static func cleanDirectory(_ directoryURL: URL, preserving preservedURL: URL, policy: ScreenSnapshotCachePolicy) throws {
        let snapshots = try snapshotFiles(in: directoryURL)
        let preservedPath = preservedURL.standardizedFileURL.path
        let cutoffDate = policy.now().addingTimeInterval(-policy.maximumAge)

        for snapshot in snapshots where snapshot.url.standardizedFileURL.path != preservedPath && snapshot.modified < cutoffDate {
            try FileManager.default.removeItem(at: snapshot.url)
        }

        let retained = snapshots.filter { snapshot in
            snapshot.url.standardizedFileURL.path == preservedPath || snapshot.modified >= cutoffDate
        }
        for snapshot in retained.dropFirst(policy.maximumFileCount) where snapshot.url.standardizedFileURL.path != preservedPath {
            try FileManager.default.removeItem(at: snapshot.url)
        }
    }

    private static func snapshotFiles(in directoryURL: URL) throws -> [SnapshotFile] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.lastPathComponent.hasPrefix("screen-") && $0.pathExtension == "png" }
            .map { fileURL in
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                let modifiedDate = values?.contentModificationDate ?? Date.distantPast
                return SnapshotFile(url: fileURL, modified: modifiedDate)
            }
            .sorted { lhs, rhs in
                lhs.modified == rhs.modified ? lhs.url.path > rhs.url.path : lhs.modified > rhs.modified
            }
    }

    private struct SnapshotFile {
        let url: URL
        let modified: Date
    }
}
