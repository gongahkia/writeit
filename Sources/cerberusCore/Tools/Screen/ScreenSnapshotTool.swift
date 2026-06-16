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

    public init(outputDirectoryURL: URL = ScreenSnapshotTool.defaultOutputDirectoryURL()) {
        self.outputDirectoryURL = outputDirectoryURL
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        guard CGPreflightScreenCaptureAccess() else {
            throw ToolExecutionError.denied("Screen Recording access is not granted.")
        }

        let image = try await ScreenCaptureSupport.captureMainDisplayImage()
        let fileURL = outputDirectoryURL
            .appendingPathComponent(Self.fileName(for: Date()), isDirectory: false)
        try ScreenCaptureSupport.writePNG(image, to: fileURL)
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
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        return baseURL
            .appendingPathComponent(CerberusCore.appName, isDirectory: true)
            .appendingPathComponent("screen-snapshots", isDirectory: true)
    }

    private static func fileName(for date: Date) -> String {
        "screen-\(Int(date.timeIntervalSince1970))-\(UUID().uuidString).png"
    }
}
