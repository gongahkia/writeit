import Foundation

@MainActor
final class AIEnhancer: TextEnhancing {
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
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    urlRequest.httpBody = try JSONEncoder().encode(body)
    do {
      AppLog.cleanup.info("cleanup_request_started")
      let (data, response) = try await URLSession.shared.data(for: urlRequest)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw AICleanupContractError.invalidResponse
      }
      return try JSONDecoder().decode(AICleanupChatResponse.self, from: data).cleanedText(
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
}
