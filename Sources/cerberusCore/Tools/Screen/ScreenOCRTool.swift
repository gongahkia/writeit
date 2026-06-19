import CoreGraphics
import Foundation
import FoundationModels
import Vision

public struct ScreenOCRTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let limit: Int
        public let scope: String?

        public init(limit: Int = 20, scope: String? = nil) {
            self.limit = limit
            self.scope = scope
        }
    }

    public let name = "screen.ocr"
    public let capability = "Read visible text from the main display or active window using local OCR."
    public let mutatesState = false
    public let argumentSchema = #"{"limit":20,"scope":"main_display|active_window"}"#

    private let hasScreenCaptureAccess: @Sendable () -> Bool

    public init(hasScreenCaptureAccess: @escaping @Sendable () -> Bool = CGPreflightScreenCaptureAccess) {
        self.hasScreenCaptureAccess = hasScreenCaptureAccess
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        guard hasScreenCaptureAccess() else {
            throw ToolExecutionError.denied("Screen Recording access is not granted.")
        }

        let requestedScope = try ScreenCaptureScope.parse(arguments.scope)
        let capture = try await ScreenCaptureSupport.captureImage(scope: requestedScope)
        let image = capture.image
        let limit = ToolArgumentSupport.clampLimit(arguments.limit, default: 20, maximum: 50)
        let observations = try recognizeText(in: image, limit: limit)
        let imageSize = CGSize(width: image.width, height: image.height)
        let payload = Self.payload(
            for: observations,
            imageSize: imageSize,
            scope: capture.scope,
            sourceDescription: capture.sourceDescription
        )

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: observations.count == 1 ? "Found 1 text item on \(capture.scope.spokenDescription)." : "Found \(observations.count) text items on \(capture.scope.spokenDescription).",
            untrustedPayload: payload,
            metadata: [
                "count": "\(observations.count)",
                "imageWidth": "\(image.width)",
                "imageHeight": "\(image.height)",
                "scope": capture.scope.rawValue
            ]
        )
    }

    static func payload(
        for observations: [ScreenTextObservation],
        imageSize: CGSize,
        scope: ScreenCaptureScope = .mainDisplay,
        sourceDescription: String = "main display"
    ) -> String {
        let header = "scope: \(scope.rawValue); source: \(sourceDescription); image: \(Int(imageSize.width))x\(Int(imageSize.height)); boxes use Vision normalized origin bottom-left and pixel origin top-left."
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
