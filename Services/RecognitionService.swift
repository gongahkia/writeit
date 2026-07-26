import Vision

struct VisionTextCandidate: Equatable, Sendable {
  let text: String
  let confidence: Float
}

protocol VisionTextRecognizing: Sendable {
  func recognize(
    image: CGImage,
    languageIdentifier: String,
    customWords: [String]
  ) throws -> [VisionTextCandidate]
}

struct LiveVisionTextRecognizer: VisionTextRecognizing {
  func recognize(
    image: CGImage,
    languageIdentifier: String,
    customWords: [String]
  ) throws -> [VisionTextCandidate] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = [languageIdentifier]
    request.customWords = customWords
    request.minimumTextHeight = 0.012
    let handler = VNImageRequestHandler(cgImage: image)
    try handler.perform([request])
    return (request.results ?? [])
      .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
      .compactMap { observation in
        observation.topCandidates(1).first.map {
          VisionTextCandidate(text: $0.string, confidence: $0.confidence)
        }
      }
  }
}

actor RecognitionService: TextRecognizing {
  private struct Configuration {
    let capabilities: RecognitionBackendCapabilities
    let visionLanguageIdentifiers: [RecognitionLanguage: String]
  }

  nonisolated let capabilities: RecognitionBackendCapabilities
  private let visionLanguageIdentifiers: [RecognitionLanguage: String]
  private let vision: any VisionTextRecognizing
  private let enhanced = EnhancedOCRAdapter()

  init() {
    let configuration = Self.makeConfiguration()
    capabilities = configuration.capabilities
    visionLanguageIdentifiers = configuration.visionLanguageIdentifiers
    vision = LiveVisionTextRecognizer()
  }

  init(
    capabilities: RecognitionBackendCapabilities,
    visionLanguageIdentifiers: [RecognitionLanguage: String],
    vision: any VisionTextRecognizing
  ) {
    self.capabilities = capabilities
    self.visionLanguageIdentifiers = visionLanguageIdentifiers
    self.vision = vision
  }

  func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult {
    try Task.checkCancellation()
    guard let preprocessed = HandwritingImagePreprocessor.process(request.imageData) else {
      throw RecognitionError.invalidImage
    }
    let image = preprocessed.image
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
      languageResolution: languageResolution,
      customWords: request.customWords.words
    )
    try Task.checkCancellation()
    if let local = try await enhanced.recognize(imageData: request.imageData) {
      return local.confidence > vision.confidence ? local : vision
    }
    return vision
  }

  private func runVision(
    _ image: CGImage,
    languageIdentifier: String,
    languageResolution: RecognitionLanguageResolution,
    customWords: [String]
  ) throws
    -> RecognitionResult
  {
    let candidates: [VisionTextCandidate]
    do {
      try Task.checkCancellation()
      candidates = try vision.recognize(
        image: image,
        languageIdentifier: languageIdentifier,
        customWords: customWords
      )
      try Task.checkCancellation()
    } catch {
      if Task.isCancelled { throw CancellationError() }
      AppLog.recognition.error(
        "vision_request_failed type=\(AppLog.errorType(error), privacy: .public)"
      )
      throw RecognitionError.failed("Apple Vision could not analyze this capture.")
    }
    guard !candidates.isEmpty else { throw RecognitionError.noText }
    return RecognitionResult(
      text: TextSanitizer.normalize(candidates.map(\.text).joined(separator: " ")),
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
  private let trocr = TrOCRCoreMLAdapter()

  func recognize(imageData: Data) async throws -> RecognitionResult? {
    try await trocr.recognize(imageData: imageData)
  }
}

enum TextSanitizer {
  static func normalize(_ input: String) -> String {
    let trimmed = input.precomposedStringWithCanonicalMapping.trimmingCharacters(
      in: .whitespacesAndNewlines)
    return trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }
}
