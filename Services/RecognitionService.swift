import ImageIO
import Vision

actor RecognitionService: TextRecognizing {
  private struct Configuration {
    let capabilities: RecognitionBackendCapabilities
    let visionLanguageIdentifiers: [RecognitionLanguage: String]
  }

  nonisolated let capabilities: RecognitionBackendCapabilities
  private let visionLanguageIdentifiers: [RecognitionLanguage: String]
  private let enhanced = EnhancedOCRAdapter()

  init() {
    let configuration = Self.makeConfiguration()
    capabilities = configuration.capabilities
    visionLanguageIdentifiers = configuration.visionLanguageIdentifiers
  }

  func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult {
    try Task.checkCancellation()
    guard let image = image(from: request.imageData) else { throw RecognitionError.invalidImage }
    guard let languageResolution = capabilities.resolve(request.language),
      let languageIdentifier = visionLanguageIdentifiers[languageResolution.resolved]
    else {
      throw RecognitionError.unavailable(
        "Apple Vision does not support \(request.language.displayName) on this Mac."
      )
    }
    let vision = try runVision(
      image,
      languageIdentifier: languageIdentifier,
      languageResolution: languageResolution
    )
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

  private func runVision(
    _ image: CGImage,
    languageIdentifier: String,
    languageResolution: RecognitionLanguageResolution
  ) throws
    -> RecognitionResult
  {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = [languageIdentifier]
    request.minimumTextHeight = 0.012
    let handler = VNImageRequestHandler(cgImage: image)
    do {
      try handler.perform([request])
    } catch {
      AppLog.recognition.error(
        "vision_request_failed type=\(AppLog.errorType(error), privacy: .public)"
      )
      throw RecognitionError.failed("Apple Vision could not analyze this capture.")
    }
    let results = (request.results ?? []).sorted { $0.boundingBox.minY > $1.boundingBox.minY }
    let candidates = results.compactMap { $0.topCandidates(1).first }
    guard !candidates.isEmpty else { throw RecognitionError.noText }
    return RecognitionResult(
      text: TextSanitizer.normalize(candidates.map(\.string).joined(separator: " ")),
      confidence: candidates.map(\.confidence).reduce(0, +) / Float(candidates.count),
      backendID: "apple-vision",
      languageResolution: languageResolution
    )
  }

  private static func makeConfiguration() -> Configuration {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    do {
      let supportedIdentifiers = try request.supportedRecognitionLanguages()
      let identifiers = Dictionary(
        uniqueKeysWithValues: RecognitionLanguage.allCases.compactMap { language in
          visionIdentifier(for: language, in: supportedIdentifiers).map { (language, $0) }
        })
      return Configuration(
        capabilities: RecognitionBackendCapabilities(
          identifier: "apple-vision",
          displayName: "Apple Vision",
          supportedLanguages: Set(identifiers.keys),
          isLocal: true,
          supportsStreaming: false,
          availability: .available
        ),
        visionLanguageIdentifiers: identifiers
      )
    } catch {
      return Configuration(
        capabilities: RecognitionBackendCapabilities(
          identifier: "apple-vision",
          displayName: "Apple Vision",
          supportedLanguages: [],
          isLocal: true,
          supportsStreaming: false,
          availability: .unavailable("Apple Vision language discovery failed.")
        ),
        visionLanguageIdentifiers: [:]
      )
    }
  }

  private static func visionIdentifier(
    for language: RecognitionLanguage,
    in identifiers: [String]
  ) -> String? {
    identifiers.first(where: { $0.caseInsensitiveCompare(language.rawValue) == .orderedSame })
      ?? identifiers.first(where: {
        $0.split(separator: "-").first?.caseInsensitiveCompare(
          language.rawValue.split(separator: "-").first ?? ""
        ) == .orderedSame
      })
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
