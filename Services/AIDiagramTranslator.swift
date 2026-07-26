import Foundation

@MainActor
final class AIDiagramTranslator: DiagramTranslating {
  private let requester: any AICleanupRequesting

  init(requester: any AICleanupRequesting = AICleanupURLSession()) {
    self.requester = requester
  }

  func translate(_ request: AIDiagramTranslationRequest) async throws -> AIDiagramTranslation? {
    guard request.enabled else { return nil }
    let keyData = try KeychainStore.data(for: "ai-api-key")
    guard let keyData,
      let key = String(data: keyData, encoding: .utf8),
      key.isEmpty == false,
      let url = URL(string: request.baseURL)
    else { return nil }
    let body = try AIDiagramChatRequest(request: request)
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.timeoutInterval = AICleanupTransportPolicy.timeoutInterval
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    urlRequest.httpBody = try JSONEncoder().encode(body)
    do {
      AppLog.cleanup.info("diagram_translation_request_started")
      let response = try await send(urlRequest)
      guard response.statusCode == 200 else { throw AIDiagramTranslationError.invalidResponse }
      return try JSONDecoder().decode(AIDiagramChatResponse.self, from: response.data).translation()
    } catch {
      if error is CancellationError { throw error }
      AppLog.cleanup.error(
        "diagram_translation_request_failed type=\(AppLog.errorType(error), privacy: .public)")
      throw RecognitionError.failed("AI diagram translation is unavailable.")
    }
  }

  private func send(_ request: URLRequest) async throws -> AICleanupHTTPResponse {
    for attempt in 1...AICleanupTransportPolicy.maximumAttempts {
      try Task.checkCancellation()
      do {
        let response = try await requester.data(for: request)
        guard AICleanupTransportPolicy.shouldRetry(statusCode: response.statusCode),
          attempt < AICleanupTransportPolicy.maximumAttempts
        else { return response }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        guard AICleanupTransportPolicy.shouldRetry(error: error),
          attempt < AICleanupTransportPolicy.maximumAttempts
        else { throw error }
      }
      try await Task.sleep(for: AICleanupTransportPolicy.retryDelay)
    }
    throw URLError(.unknown)
  }
}
