import CoreGraphics
import Foundation
import FoundationModels
import ScreenCaptureKit
import Vision

public struct ScreenOCRTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let limit: Int

        public init(limit: Int = 20) {
            self.limit = limit
        }
    }

    public let name = "screen.ocr"
    public let capability = "Read visible text from the main display using local OCR."
    public let mutatesState = false
    public let argumentSchema = #"{"limit":20}"#

    public init() {}

    public func run(arguments: Arguments) async throws -> ToolResult {
        guard CGPreflightScreenCaptureAccess() else {
            throw ToolExecutionError.denied("Screen Recording access is not granted.")
        }

        let image = try await captureMainDisplayImage()
        let limit = ToolArgumentSupport.clampLimit(arguments.limit, default: 20, maximum: 50)
        let observations = try recognizeText(in: image, limit: limit)
        let payload = observations
            .map { "- \($0.text) [confidence: \(String(format: "%.2f", $0.confidence))]" }
            .joined(separator: "\n")

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: observations.count == 1 ? "Found 1 text item on screen." : "Found \(observations.count) text items on screen.",
            untrustedPayload: payload,
            metadata: ["count": "\(observations.count)"]
        )
    }

    private func captureMainDisplayImage() async throws -> CGImage {
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

    private func recognizeText(in image: CGImage, limit: Int) throws -> [ScreenTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return (request.results ?? [])
            .compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else {
                    return nil
                }
                return ScreenTextObservation(text: candidate.string, confidence: candidate.confidence)
            }
            .prefix(limit)
            .map { $0 }
    }
}

private struct ScreenTextObservation: Sendable {
    let text: String
    let confidence: Float
}
