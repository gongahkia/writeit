import ImageIO
import Vision

actor RecognitionService: TextRecognizing {
  nonisolated let capabilities = RecognitionBackendCapabilities(
    identifier: "apple-vision",
    displayName: "Apple Vision",
    supportedLanguages: [.english],
    isLocal: true
  )
  private let enhanced = EnhancedOCRAdapter()

  func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult {
    try Task.checkCancellation()
    guard let image = image(from: request.imageData) else { throw RecognitionError.invalidImage }
    let vision = try runVision(image, language: request.language)
    try Task.checkCancellation()
    if let local = try await enhanced.recognize(imageData: request.imageData) {
      return local.confidence > vision.confidence ? local : vision
    }
    return vision
  }

  private func image(from data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  private func runVision(_ image: CGImage, language: RecognitionLanguage) throws
    -> RecognitionResult
  {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = [language.rawValue]
    request.minimumTextHeight = 0.012
    let handler = VNImageRequestHandler(cgImage: image)
    do {
      try handler.perform([request])
    } catch {
      throw RecognitionError.failed("Apple Vision could not analyze this capture.")
    }
    let results = (request.results ?? []).sorted { $0.boundingBox.minY > $1.boundingBox.minY }
    let candidates = results.compactMap { $0.topCandidates(1).first }
    guard !candidates.isEmpty else { throw RecognitionError.noText }
    return RecognitionResult(
      text: TextSanitizer.normalize(candidates.map(\.string).joined(separator: " ")),
      confidence: candidates.map(\.confidence).reduce(0, +) / Float(candidates.count),
      backendID: "apple-vision"
    )
  }
}

actor EnhancedOCRAdapter {
  func recognize(imageData: Data) async throws -> RecognitionResult? {
    nil
  }
}

enum TextSanitizer {
  static func normalize(_ input: String) -> String {
    let trimmed = input.precomposedStringWithCanonicalMapping.trimmingCharacters(
      in: .whitespacesAndNewlines)
    return trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }
}
