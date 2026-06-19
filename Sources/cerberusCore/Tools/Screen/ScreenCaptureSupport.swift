import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

public enum ScreenCaptureScope: String, Codable, Sendable {
    case mainDisplay = "main_display"
    case activeWindow = "active_window"

    static func parse(_ rawValue: String?) throws -> ScreenCaptureScope {
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else {
            return .mainDisplay
        }
        guard let scope = ScreenCaptureScope(rawValue: value) else {
            throw ToolExecutionError.invalidArguments("Screen capture scope must be main_display or active_window.")
        }
        return scope
    }

    var spokenDescription: String {
        switch self {
        case .mainDisplay:
            "the main display"
        case .activeWindow:
            "the active window"
        }
    }
}

struct CapturedScreenImage {
    let image: CGImage
    let scope: ScreenCaptureScope
    let sourceDescription: String
}

enum ScreenCaptureSupport {
    static func captureImage(scope: ScreenCaptureScope) async throws -> CapturedScreenImage {
        switch scope {
        case .mainDisplay:
            let image = try await captureMainDisplayImage()
            return CapturedScreenImage(image: image, scope: scope, sourceDescription: "main display")
        case .activeWindow:
            return try await captureActiveWindowImage()
        }
    }

    private static func captureMainDisplayImage() async throws -> CGImage {
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

    private static func captureActiveWindowImage() async throws -> CapturedScreenImage {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.isActive && $0.isOnScreen && $0.windowLayer == 0 }) else {
            throw ToolExecutionError.denied("No active window is available for screen capture.")
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        let contentRect = filter.contentRect.isEmpty ? window.frame : filter.contentRect
        configuration.width = max(1, Int((contentRect.width * scale).rounded()))
        configuration.height = max(1, Int((contentRect.height * scale).rounded()))
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = false

        let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, any Error>) in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: ToolExecutionError.denied("Could not capture the active window."))
                }
            }
        }

        let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceDescription = title?.isEmpty == false ? "active window: \(title!)" : "active window"
        return CapturedScreenImage(image: image, scope: .activeWindow, sourceDescription: sourceDescription)
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

    static func crop(_ image: CGImage, to region: ScreenOCRRegion) throws -> CGImage {
        guard region != .full else {
            return image
        }

        let cropRect = CGRect(
            x: (region.x * Double(image.width)).rounded(.down),
            y: (region.y * Double(image.height)).rounded(.down),
            width: max(1, (region.width * Double(image.width)).rounded()),
            height: max(1, (region.height * Double(image.height)).rounded())
        ).integral
        guard let croppedImage = image.cropping(to: cropRect) else {
            throw ToolExecutionError.invalidArguments("Screen OCR region could not be cropped.")
        }
        return croppedImage
    }
}
