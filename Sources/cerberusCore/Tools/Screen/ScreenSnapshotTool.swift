import CoreGraphics
import Foundation
import FoundationModels

public struct ScreenSnapshotTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public init() {}
    }

    public let name = "screen.snapshot"
    public let capability = "Capture the main display to a local PNG file for user-visible screen context."
    public let mutatesState = false
    public let argumentSchema = #"{}"#

    private let outputDirectoryURL: URL
    private let cachePolicy: ScreenSnapshotCachePolicy

    public init(
        outputDirectoryURL: URL = ScreenSnapshotTool.defaultOutputDirectoryURL(),
        cachePolicy: ScreenSnapshotCachePolicy = .default
    ) {
        self.outputDirectoryURL = outputDirectoryURL
        self.cachePolicy = cachePolicy
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        guard CGPreflightScreenCaptureAccess() else {
            throw ToolExecutionError.denied("Screen Recording access is not granted.")
        }

        let image = try await ScreenCaptureSupport.captureMainDisplayImage()
        let fileURL = outputDirectoryURL
            .appendingPathComponent(Self.fileName(for: Date()), isDirectory: false)
        try ScreenCaptureSupport.writePNG(image, to: fileURL)
        try ScreenSnapshotCachePolicy.cleanDirectory(outputDirectoryURL, preserving: fileURL, policy: cachePolicy)
        let imageSize = CGSize(width: image.width, height: image.height)

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "Captured the main display.",
            untrustedPayload: Self.payload(fileURL: fileURL, imageSize: imageSize),
            metadata: [
                "imagePath": fileURL.path,
                "imageWidth": "\(image.width)",
                "imageHeight": "\(image.height)"
            ]
        )
    }

    static func payload(fileURL: URL, imageSize: CGSize) -> String {
        """
        Screen snapshot saved.
        file: \(fileURL.path)
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

    static func cleanDirectory(_ directoryURL: URL, preserving preservedURL: URL, policy: ScreenSnapshotCachePolicy) throws {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let preservedPath = preservedURL.standardizedFileURL.path
        let cutoffDate = policy.now().addingTimeInterval(-policy.maximumAge)
        let snapshots: [SnapshotFile] = files
            .filter { $0.lastPathComponent.hasPrefix("screen-") && $0.pathExtension == "png" }
            .map { fileURL in
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                let modifiedDate = values?.contentModificationDate ?? Date.distantPast
                return SnapshotFile(url: fileURL, modified: modifiedDate)
            }
            .sorted { lhs, rhs in
                lhs.modified == rhs.modified ? lhs.url.path > rhs.url.path : lhs.modified > rhs.modified
            }

        for snapshot in snapshots where snapshot.url.standardizedFileURL.path != preservedPath && snapshot.modified < cutoffDate {
            try fileManager.removeItem(at: snapshot.url)
        }

        let retained = snapshots.filter { snapshot in
            snapshot.url.standardizedFileURL.path == preservedPath || snapshot.modified >= cutoffDate
        }
        for snapshot in retained.dropFirst(policy.maximumFileCount) where snapshot.url.standardizedFileURL.path != preservedPath {
            try fileManager.removeItem(at: snapshot.url)
        }
    }

    private struct SnapshotFile {
        let url: URL
        let modified: Date
    }
}
