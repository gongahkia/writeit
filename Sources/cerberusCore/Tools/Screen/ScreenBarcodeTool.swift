import CoreGraphics
import Foundation
import FoundationModels
import Vision

public struct ScreenBarcodeTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let limit: Int
        public let scope: String?
        public let regionX: Double?
        public let regionY: Double?
        public let regionWidth: Double?
        public let regionHeight: Double?

        public init(
            limit: Int = 10,
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

    public let name = "screen.barcodes"
    public let capability = "Detect visible barcodes and QR codes from the main display, active window, or a normalized region using local Vision."
    public let mutatesState = false
    public let argumentSchema = #"{"limit":10,"scope":"main_display|active_window","regionX":0.0,"regionY":0.0,"regionWidth":1.0,"regionHeight":1.0}"#

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
        let limit = ToolArgumentSupport.clampLimit(arguments.limit, default: 10, maximum: 50)
        let observations = try detectBarcodes(in: image, limit: limit)
        let imageSize = CGSize(width: image.width, height: image.height)

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: observations.count == 1 ? "Found 1 barcode on \(capture.scope.spokenDescription)." : "Found \(observations.count) barcodes on \(capture.scope.spokenDescription).",
            untrustedPayload: Self.payload(
                for: observations,
                imageSize: imageSize,
                scope: capture.scope,
                sourceDescription: capture.sourceDescription,
                region: region
            ),
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
        for observations: [ScreenBarcodeObservation],
        imageSize: CGSize,
        scope: ScreenCaptureScope = .mainDisplay,
        sourceDescription: String = "main display",
        region: ScreenOCRRegion = .full
    ) -> String {
        let header = "scope: \(scope.rawValue); source: \(sourceDescription); region: \(region.description); image: \(Int(imageSize.width))x\(Int(imageSize.height)); boxes use Vision normalized origin bottom-left and pixel origin top-left."
        guard !observations.isEmpty else {
            return "\(header)\nNo barcodes recognized."
        }

        return ([header] + observations.map { observation in
            let pixelRect = observation.pixelRect(in: imageSize)
            let payload = observation.payloadString.map(ScreenTextRedactor.redact) ?? "<binary payload>"
            return "- \(payload) [symbology: \(observation.symbology), confidence: \(format(observation.confidence)), normalizedBox: \(format(observation.boundingBox)), pixelBox: \(format(pixelRect))]"
        }).joined(separator: "\n")
    }

    func detectBarcodes(in image: CGImage, limit: Int) throws -> [ScreenBarcodeObservation] {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return (request.results ?? [])
            .map { observation in
                ScreenBarcodeObservation(
                    payloadString: observation.payloadStringValue,
                    symbology: String(describing: observation.symbology),
                    confidence: observation.confidence,
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

struct ScreenBarcodeObservation: Sendable {
    let payloadString: String?
    let symbology: String
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
