import CoreGraphics
import Foundation
import FoundationModels
import Vision

public struct ScreenOCRTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let limit: Int
        public let scope: String?
        public let regionX: Double?
        public let regionY: Double?
        public let regionWidth: Double?
        public let regionHeight: Double?

        public init(
            limit: Int = 20,
            scope: String? = nil,
            regionX: Double? = nil,
            regionY: Double? = nil,
            regionWidth: Double? = nil,
            regionHeight: Double? = nil
        ) {
            self.limit = limit
            self.scope = scope
            self.regionX = regionX
            self.regionY = regionY
            self.regionWidth = regionWidth
            self.regionHeight = regionHeight
        }
    }

    public let name = "screen.ocr"
    public let capability = "Read visible text from the main display, active window, or a normalized region using local OCR."
    public let mutatesState = false
    public let argumentSchema = #"{"limit":20,"scope":"main_display|active_window","regionX":0.0,"regionY":0.0,"regionWidth":1.0,"regionHeight":1.0}"#

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
        let region = try ScreenOCRRegion.parse(
            x: arguments.regionX,
            y: arguments.regionY,
            width: arguments.regionWidth,
            height: arguments.regionHeight
        )
        let image = try ScreenCaptureSupport.crop(capture.image, to: region)
        let limit = ToolArgumentSupport.clampLimit(arguments.limit, default: 20, maximum: 50)
        let observations = try recognizeText(in: image, limit: limit)
        let imageSize = CGSize(width: image.width, height: image.height)
        let payload = Self.payload(
            for: observations,
            imageSize: imageSize,
            scope: capture.scope,
            sourceDescription: capture.sourceDescription,
            region: region
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
                "scope": capture.scope.rawValue,
                "region": region.description
            ]
        )
    }

    static func payload(
        for observations: [ScreenTextObservation],
        imageSize: CGSize,
        scope: ScreenCaptureScope = .mainDisplay,
        sourceDescription: String = "main display",
        region: ScreenOCRRegion = .full
    ) -> String {
        let header = "scope: \(scope.rawValue); source: \(sourceDescription); region: \(region.description); image: \(Int(imageSize.width))x\(Int(imageSize.height)); boxes use Vision normalized origin bottom-left and pixel origin top-left."
        guard !observations.isEmpty else {
            return "\(header)\nNo text recognized."
        }

        return ([header] + observations.map { observation in
            let pixelRect = observation.pixelRect(in: imageSize)
            return "- \(ScreenTextRedactor.redact(observation.text)) [confidence: \(format(observation.confidence)), normalizedBox: \(format(observation.boundingBox)), pixelBox: \(format(pixelRect))]"
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

public struct ScreenOCRRegion: Equatable, Sendable, CustomStringConvertible {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public static let full = ScreenOCRRegion(x: 0, y: 0, width: 1, height: 1)

    public var description: String {
        "x=\(Self.format(x)) y=\(Self.format(y)) w=\(Self.format(width)) h=\(Self.format(height))"
    }

    public static func parse(
        x: Double?,
        y: Double?,
        width: Double?,
        height: Double?
    ) throws -> ScreenOCRRegion {
        let hasAnyRegionValue = [x, y, width, height].contains { $0 != nil }
        guard hasAnyRegionValue else {
            return .full
        }
        guard let x, let y, let width, let height else {
            throw ToolExecutionError.invalidArguments("Screen OCR region requires regionX, regionY, regionWidth, and regionHeight.")
        }
        guard x >= 0, y >= 0, width > 0, height > 0, x + width <= 1, y + height <= 1 else {
            throw ToolExecutionError.invalidArguments("Screen OCR region values must define a normalized rectangle inside 0...1.")
        }
        return ScreenOCRRegion(x: x, y: y, width: width, height: height)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
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
