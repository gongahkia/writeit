import Foundation

enum AICleanupContractError: LocalizedError, Equatable {
  case invalidModel
  case emptyInput
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .invalidModel: "AI cleanup model is invalid."
    case .emptyInput: "AI cleanup requires recognized text."
    case .invalidResponse: "AI cleanup did not return usable text."
    }
  }
}

struct AICleanupChatRequest: Encodable, Sendable, Equatable {
  struct Message: Encodable, Sendable, Equatable {
    let role: String
    let content: String
  }

  static let systemInstruction =
    "Correct only obvious handwriting OCR errors. Preserve wording, intent, and formatting. Return only corrected text."

  let model: String
  let messages: [Message]
  let temperature: Double
  let n: Int
  let stream: Bool

  init(model: String, text: String) throws {
    let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
    guard model.isEmpty == false else { throw AICleanupContractError.invalidModel }
    guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    else { throw AICleanupContractError.emptyInput }
    self.model = model
    messages = [
      Message(role: "system", content: Self.systemInstruction),
      Message(role: "user", content: text),
    ]
    temperature = 0
    n = 1
    stream = false
  }
}

struct AICleanupChatResponse: Decodable, Sendable {
  struct Choice: Decodable, Sendable {
    struct Message: Decodable, Sendable {
      let content: String?
    }

    let message: Message
  }

  let choices: [Choice]

  func cleanedText() throws -> String {
    guard let content = choices.first?.message.content else {
      throw AICleanupContractError.invalidResponse
    }
    let cleaned = TextSanitizer.normalize(content)
    guard cleaned.isEmpty == false else { throw AICleanupContractError.invalidResponse }
    return cleaned
  }
}
