import Foundation

struct AzureVisionHTTPResponse: Sendable {
  let data: Data
  let statusCode: Int
}

protocol AzureVisionRequesting: Sendable {
  func data(for request: URLRequest) async throws -> AzureVisionHTTPResponse
}

struct URLSessionAzureVisionRequester: AzureVisionRequesting {
  func data(for request: URLRequest) async throws -> AzureVisionHTTPResponse {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    return AzureVisionHTTPResponse(data: data, statusCode: response.statusCode)
  }
}

actor AzureVisionRecognitionService: TextRecognizing, CloudCredentialValidating {
  nonisolated let capabilities = RecognitionBackendCapabilities(
    identifier: "azure-ai-vision-read",
    displayName: "Azure AI Vision Read",
    supportedLanguages: Set(RecognitionLanguage.allCases),
    isLocal: false,
    supportsStreaming: false,
    availability: .available
  )

  private let endpoint: URL
  private let apiKey: String
  private let requester: any AzureVisionRequesting

  init(
    endpoint: URL,
    apiKey: String,
    requester: any AzureVisionRequesting = URLSessionAzureVisionRequester()
  ) {
    self.endpoint = endpoint
    self.apiKey = apiKey
    self.requester = requester
  }

  func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult {
    try Task.checkCancellation()
    guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      Self.isAzureEndpoint(endpoint)
    else {
      throw RecognitionError.unavailable("Azure AI Vision is not configured.")
    }
    let response = try await send(request)
    try Task.checkCancellation()
    guard (200...299).contains(response.statusCode) else {
      AppLog.recognition.error(
        "azure_vision_request_failed status=\(response.statusCode, privacy: .public)"
      )
      throw RecognitionError.unavailable("Azure AI Vision is unavailable.")
    }
    let body: AzureVisionResponse
    do {
      body = try JSONDecoder().decode(AzureVisionResponse.self, from: response.data)
    } catch {
      AppLog.recognition.error("azure_vision_response_invalid")
      throw RecognitionError.failed("Azure AI Vision returned an invalid response.")
    }
    guard body.error == nil else {
      throw RecognitionError.failed("Azure AI Vision could not analyze this capture.")
    }
    guard let readResult = body.readResult else { throw RecognitionError.noText }
    let text = Self.normalizedText(readResult.content ?? readResult.lineText)
    guard !text.isEmpty else { throw RecognitionError.noText }
    let confidences = readResult.wordConfidences
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

  func validateCredentials() async -> CloudCredentialValidation {
    guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      Self.isAzureEndpoint(endpoint)
    else {
      return .notConfigured
    }
    do {
      let response = try await send(
        RecognitionRequest(imageData: CloudCredentialValidationProbe.imageData, language: .english))
      switch response.statusCode {
      case 200...299: return .valid
      case 401, 403: return .invalidCredentials
      default: return .unavailable
      }
    } catch is CancellationError {
      return .cancelled
    } catch {
      return .unavailable
    }
  }

  private func send(_ request: RecognitionRequest) async throws -> AzureVisionHTTPResponse {
    let url = try requestURL(for: request.language)
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
    urlRequest.httpBody = request.imageData
    do {
      AppLog.recognition.info("azure_vision_request_started")
      return try await requester.data(for: urlRequest)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      AppLog.recognition.error(
        "azure_vision_request_failed type=\(AppLog.errorType(error), privacy: .public)"
      )
      throw RecognitionError.unavailable("Azure AI Vision is unavailable.")
    }
  }

  private func requestURL(for language: RecognitionLanguage) throws -> URL {
    let route = endpoint.appendingPathComponent("computervision")
      .appendingPathComponent("imageanalysis:analyze")
    guard var components = URLComponents(url: route, resolvingAgainstBaseURL: false) else {
      throw RecognitionError.unavailable("Azure AI Vision is not configured.")
    }
    components.queryItems = [
      URLQueryItem(name: "api-version", value: "2024-02-01"),
      URLQueryItem(name: "features", value: "read"),
      URLQueryItem(name: "language", value: Self.azureLanguage(for: language)),
    ]
    guard let url = components.url else {
      throw RecognitionError.unavailable("Azure AI Vision is not configured.")
    }
    return url
  }

  private static func isAzureEndpoint(_ endpoint: URL) -> Bool {
    guard endpoint.scheme?.lowercased() == "https", let host = endpoint.host?.lowercased() else {
      return false
    }
    return host == "api.cognitive.microsoft.com" || host.hasSuffix(".cognitiveservices.azure.com")
  }

  private static func azureLanguage(for language: RecognitionLanguage) -> String {
    switch language {
    case .english: "en"
    case .french: "fr"
    case .german: "de"
    case .spanish: "es"
    case .italian: "it"
    case .portuguese: "pt"
    }
  }

  private static func normalizedText(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
      .precomposedStringWithCanonicalMapping
  }
}

private struct AzureVisionResponse: Decodable {
  struct ServiceError: Decodable {}

  struct ReadResult: Decodable {
    struct Block: Decodable {
      struct Line: Decodable {
        struct Word: Decodable { let confidence: Float? }
        let text: String?
        let words: [Word]?
      }
      let lines: [Line]?
    }

    let content: String?
    let blocks: [Block]?

    var lineText: String {
      (blocks ?? []).flatMap { $0.lines ?? [] }
        .compactMap(\.text)
        .joined(separator: " ")
    }

    var wordConfidences: [Float] {
      (blocks ?? []).flatMap { block in
        (block.lines ?? []).flatMap { line in
          (line.words ?? []).compactMap(\.confidence)
        }
      }
    }
  }

  let readResult: ReadResult?
  let error: ServiceError?
}
