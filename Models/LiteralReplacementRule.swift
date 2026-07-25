import Foundation

enum LiteralReplacementRuleError: LocalizedError, Equatable {
  case emptyFindText

  var errorDescription: String? {
    switch self {
    case .emptyFindText: "Replacement text to find cannot be empty."
    }
  }
}

struct LiteralReplacementRule: Codable, Sendable, Equatable, Identifiable {
  let id: UUID
  let find: String
  let replacement: String

  init(id: UUID = UUID(), find: String, replacement: String) throws {
    guard find.isEmpty == false else { throw LiteralReplacementRuleError.emptyFindText }
    self.id = id
    self.find = find
    self.replacement = replacement
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(UUID.self, forKey: .id),
      find: container.decode(String.self, forKey: .find),
      replacement: container.decode(String.self, forKey: .replacement)
    )
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case find
    case replacement
  }

  func applying(to text: String) -> String {
    text.replacingOccurrences(of: find, with: replacement)
  }
}

struct LiteralReplacementRules: Codable, Sendable, Equatable {
  let rules: [LiteralReplacementRule]

  init(rules: [LiteralReplacementRule] = []) {
    self.rules = rules
  }

  func applying(to text: String) -> String {
    rules.reduce(text) { partial, rule in rule.applying(to: partial) }
  }
}
