import CoreGraphics
import Foundation
import FoundationModels
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

    private let hasScreenCaptureAccess: @Sendable () -> Bool

    public init(hasScreenCaptureAccess: @escaping @Sendable () -> Bool = CGPreflightScreenCaptureAccess) {
        self.hasScreenCaptureAccess = hasScreenCaptureAccess
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        guard hasScreenCaptureAccess() else {
            throw ToolExecutionError.denied("Screen Recording access is not granted.")
        }

        let image = try await ScreenCaptureSupport.captureMainDisplayImage()
        let limit = ToolArgumentSupport.clampLimit(arguments.limit, default: 20, maximum: 50)
        let observations = try recognizeText(in: image, limit: limit)
        let imageSize = CGSize(width: image.width, height: image.height)
        let payload = Self.payload(for: observations, imageSize: imageSize)

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: observations.count == 1 ? "Found 1 text item on screen." : "Found \(observations.count) text items on screen.",
            untrustedPayload: payload,
            metadata: [
                "count": "\(observations.count)",
                "imageWidth": "\(image.width)",
                "imageHeight": "\(image.height)"
            ]
        )
    }

    static func payload(for observations: [ScreenTextObservation], imageSize: CGSize) -> String {
        let header = "Image: \(Int(imageSize.width))x\(Int(imageSize.height)); boxes use Vision normalized origin bottom-left and pixel origin top-left."
        guard !observations.isEmpty else {
            return "\(header)\nNo text recognized."
        }

        return ([header] + observations.map { observation in
            let pixelRect = observation.pixelRect(in: imageSize)
            return "- \(observation.text) [confidence: \(format(observation.confidence)), normalizedBox: \(format(observation.boundingBox)), pixelBox: \(format(pixelRect))]"
        }).joined(separator: "\n")
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
                return ScreenTextObservation(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox
                )
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

    private static func format(_ rect: CGRect) -> String {
        "x=\(String(format: "%.2f", rect.minX)) y=\(String(format: "%.2f", rect.minY)) w=\(String(format: "%.2f", rect.width)) h=\(String(format: "%.2f", rect.height))"
    }
}

struct ScreenTextObservation: Sendable {
    let text: String
    let confidence: Float
    let boundingBox: CGRect

    func pixelRect(in imageSize: CGSize) -> CGRect {
        CGRect(
            x: boundingBox.minX * imageSize.width,
            y: (1 - boundingBox.maxY) * imageSize.height,
            width: boundingBox.width * imageSize.width,
            height: boundingBox.height * imageSize.height
        )
    }
}
