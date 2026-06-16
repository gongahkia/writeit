import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

enum ScreenCaptureSupport {
    static func captureMainDisplayImage() async throws -> CGImage {
        let bounds = CGDisplayBounds(CGMainDisplayID())

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(in: bounds) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: ToolExecutionError.denied("Could not capture the main display."))
                }
            }
        }
    }

    static func writePNG(_ image: CGImage, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ToolExecutionError.denied("Could not create screen snapshot file.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ToolExecutionError.denied("Could not write screen snapshot file.")
        }
    }
}
