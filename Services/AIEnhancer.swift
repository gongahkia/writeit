import Foundation

@MainActor
final class AIEnhancer: TextEnhancing {
  private let requester: any AICleanupRequesting

  init(requester: any AICleanupRequesting = AICleanupURLSession()) {
    self.requester = requester
  }

  func clean(_ request: TextEnhancementRequest) async throws -> String {
    guard request.enabled else { return request.text }
    let keyData: Data?
    do {
      keyData = try KeychainStore.data(for: "ai-api-key")
    } catch {
      AppLog.cleanup.error(
        "cleanup_key_read_failed type=\(AppLog.errorType(error), privacy: .public)")
      throw error
    }
    guard let keyData,
      let key = String(data: keyData, encoding: .utf8), !key.isEmpty,
      let url = URL(string: request.baseURL)
    else { return request.text }
    let body: AICleanupChatRequest
    do {
      body = try AICleanupChatRequest(model: request.model, text: request.text)
    } catch {
      return request.text
    }
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.timeoutInterval = AICleanupTransportPolicy.timeoutInterval
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    urlRequest.httpBody = try JSONEncoder().encode(body)
    do {
      AppLog.cleanup.info("cleanup_request_started")
      let response = try await send(urlRequest)
      guard response.statusCode == 200 else {
        throw AICleanupContractError.invalidResponse
      }
      return try JSONDecoder().decode(AICleanupChatResponse.self, from: response.data).cleanedText(
        for: request.text)
    } catch {
      if error is CancellationError { throw error }
      AppLog.cleanup.error(
        "cleanup_request_failed type=\(AppLog.errorType(error), privacy: .public)")
      throw RecognitionError.failed("AI cleanup is unavailable.")
    }
  }

  func saveAPIKey(_ value: String) throws {
    do {
      if value.isEmpty {
        try KeychainStore.delete("ai-api-key")
      } else {
        try KeychainStore.set(Data(value.utf8), for: "ai-api-key")
      }
    } catch {
      AppLog.cleanup.error(
        "cleanup_key_save_failed type=\(AppLog.errorType(error), privacy: .public)")
      throw error
    }
  }

  func hasAPIKey() throws -> Bool { try KeychainStore.data(for: "ai-api-key") != nil }

  func testConnection(baseURL: String, model: String) async -> AICleanupConnectionStatus {
    do {
      guard let keyData = try KeychainStore.data(for: "ai-api-key"),
        let key = String(data: keyData, encoding: .utf8), key.isEmpty == false
      else { return .notConfigured }
      return await AICleanupCapabilityDiscovery(requester: requester).discover(
        endpoint: baseURL,
        apiKey: key,
        model: model
      )
    } catch {
      return .notConfigured
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
