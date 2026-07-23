import Foundation

final class AIEnhancer {
  func clean(_ text: String, preferences: Preferences) async -> String {
    guard preferences.aiEnabled,
          let keyData = KeychainStore.data(for: "ai-api-key"),
          let key = String(data: keyData, encoding: .utf8), !key.isEmpty,
          let url = URL(string: preferences.aiBaseURL) else { return text }
    let body = ChatRequest(
      model: preferences.aiModel,
      messages: [
        .init(role: "system", content: "Correct only obvious handwriting OCR errors. Preserve wording, intent, and formatting. Return only corrected text."),
        .init(role: "user", content: text)
      ],
      temperature: 0
    )
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONEncoder().encode(body)
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200,
            let result = try? JSONDecoder().decode(ChatResponse.self, from: data),
            let cleaned = result.choices.first?.message.content,
            !cleaned.isEmpty else { return text }
      return TextSanitizer.normalize(cleaned)
    } catch {
      return text
    }
  }

  func saveAPIKey(_ value: String) {
    if value.isEmpty { KeychainStore.delete("ai-api-key") }
    else { try? KeychainStore.set(Data(value.utf8), for: "ai-api-key") }
  }

  func hasAPIKey() -> Bool { KeychainStore.data(for: "ai-api-key") != nil }
}

private struct ChatRequest: Encodable {
  struct Message: Encodable { var role: String; var content: String }
  var model: String
  var messages: [Message]
  var temperature: Double
}

private struct ChatResponse: Decodable {
  struct Choice: Decodable {
    struct Message: Decodable { var content: String }
    var message: Message
  }
  var choices: [Choice]
}
