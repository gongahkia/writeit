import Foundation

struct GoogleVisionHTTPResponse: Sendable {
  let data: Data
  let statusCode: Int
}

protocol GoogleVisionRequesting: Sendable {
  func data(for request: URLRequest) async throws -> GoogleVisionHTTPResponse
}

struct URLSessionGoogleVisionRequester: GoogleVisionRequesting {
  func data(for request: URLRequest) async throws -> GoogleVisionHTTPResponse {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    return GoogleVisionHTTPResponse(data: data, statusCode: response.statusCode)
  }
}

actor GoogleVisionRecognitionService: TextRecognizing {
  static let endpoint = URL(string: "https://vision.googleapis.com/v1/images:annotate")!

  nonisolated let capabilities = RecognitionBackendCapabilities(
    identifier: "google-cloud-vision",
    displayName: "Google Cloud Vision",
    supportedLanguages: Set(RecognitionLanguage.allCases),
    isLocal: false,
    supportsStreaming: false,
    availability: .available
  )

  private let apiKey: String
  private let requester: any GoogleVisionRequesting

  init(
    apiKey: String,
    requester: any GoogleVisionRequesting = URLSessionGoogleVisionRequester()
  ) {
    self.apiKey = apiKey
    self.requester = requester
  }

  func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult {
    try Task.checkCancellation()
    guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw RecognitionError.unavailable("Google Cloud Vision is not configured.")
    }
    let response = try await send(request)
    try Task.checkCancellation()
    guard (200...299).contains(response.statusCode) else {
      AppLog.recognition.error(
        "google_vision_request_failed status=\(response.statusCode, privacy: .public)"
      )
      throw RecognitionError.unavailable("Google Cloud Vision is unavailable.")
    }
    let body: GoogleVisionResponse
    do {
      body = try JSONDecoder().decode(GoogleVisionResponse.self, from: response.data)
    } catch {
      AppLog.recognition.error("google_vision_response_invalid")
      throw RecognitionError.failed("Google Cloud Vision returned an invalid response.")
    }
    guard let result = body.responses.first else {
      throw RecognitionError.failed("Google Cloud Vision returned no result.")
    }
    guard result.error == nil else {
      throw RecognitionError.failed("Google Cloud Vision could not analyze this capture.")
    }
    guard let rawText = result.fullTextAnnotation?.text else {
      throw RecognitionError.noText
    }
    let text = rawText.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
      .precomposedStringWithCanonicalMapping
    guard !text.isEmpty else { throw RecognitionError.noText }
    let confidences = result.fullTextAnnotation?.wordConfidences ?? []
    let confidence = confidences.isEmpty
      ? 0
      : confidences.reduce(0, +) / Float(confidences.count)
    return RecognitionResult(
      text: text,
      confidence: confidence,
      backendID: capabilities.identifier,
      languageResolution: .identity(request.language)
    )
  }

  private func send(_ request: RecognitionRequest) async throws -> GoogleVisionHTTPResponse {
    var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
    guard let url = components.url else {
      throw RecognitionError.unavailable("Google Cloud Vision is not configured.")
    }
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
    urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONEncoder().encode(
      GoogleVisionRequest(
        requests: [
          .init(
            image: .init(content: request.imageData.base64EncodedString()),
            features: [.init(type: "DOCUMENT_TEXT_DETECTION")],
            imageContext: .init(languageHints: [request.language.rawValue])
          ),
        ]
      ))
    do {
      AppLog.recognition.info("google_vision_request_started")
      return try await requester.data(for: urlRequest)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      AppLog.recognition.error(
        "google_vision_request_failed type=\(AppLog.errorType(error), privacy: .public)"
      )
      throw RecognitionError.unavailable("Google Cloud Vision is unavailable.")
    }
  }
}

private struct GoogleVisionRequest: Encodable {
  struct Request: Encodable {
    struct Image: Encodable { let content: String }
    struct Feature: Encodable { let type: String }
    struct ImageContext: Encodable { let languageHints: [String] }

    let image: Image
    let features: [Feature]
    let imageContext: ImageContext
  }

  let requests: [Request]
}

private struct GoogleVisionResponse: Decodable {
  struct Response: Decodable {
    struct ServiceError: Decodable {}
    let fullTextAnnotation: TextAnnotation?
    let error: ServiceError?
  }

  struct TextAnnotation: Decodable {
    struct Page: Decodable {
      struct Block: Decodable {
        struct Paragraph: Decodable {
          struct Word: Decodable { let confidence: Float? }
          let words: [Word]?
        }
        let paragraphs: [Paragraph]?
      }
      let blocks: [Block]?
    }

    let text: String?
    let pages: [Page]?

    var wordConfidences: [Float] {
      (pages ?? []).flatMap { page in
        (page.blocks ?? []).flatMap { block in
          (block.paragraphs ?? []).flatMap { paragraph in
            (paragraph.words ?? []).compactMap(\.confidence)
          }
        }
      }
    }
  }

  let responses: [Response]
}
