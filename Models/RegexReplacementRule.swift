import Foundation

enum RegexReplacementRuleError: LocalizedError, Equatable {
  case emptyPattern
  case invalidPattern
  case patternTooLong
  case replacementTooLong
  case tooManyRules

  var errorDescription: String? {
    switch self {
    case .emptyPattern: "Regular-expression pattern cannot be empty."
    case .invalidPattern: "Regular-expression pattern is invalid."
    case .patternTooLong: "Regular-expression pattern is too long."
    case .replacementTooLong: "Regular-expression replacement is too long."
    case .tooManyRules: "Too many regular-expression replacements."
    }
  }
}

struct RegexReplacementRule: Codable, Sendable, Equatable, Identifiable {
  static let maximumPatternLength = 512
  static let maximumReplacementLength = 2_048

  let id: UUID
  let pattern: String
  let replacement: String

  init(id: UUID = UUID(), pattern: String, replacement: String) throws {
    guard pattern.isEmpty == false else { throw RegexReplacementRuleError.emptyPattern }
    guard pattern.utf8.count <= Self.maximumPatternLength
    else { throw RegexReplacementRuleError.patternTooLong }
    guard replacement.utf8.count <= Self.maximumReplacementLength
    else { throw RegexReplacementRuleError.replacementTooLong }
    guard (try? NSRegularExpression(pattern: pattern)) != nil
    else { throw RegexReplacementRuleError.invalidPattern }
    self.id = id
    self.pattern = pattern
    self.replacement = replacement
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(UUID.self, forKey: .id),
      pattern: container.decode(String.self, forKey: .pattern),
      replacement: container.decode(String.self, forKey: .replacement)
    )
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case pattern
    case replacement
  }
}

struct RegexReplacementRules: Codable, Sendable, Equatable {
  static let maximumRuleCount = 16

  let rules: [RegexReplacementRule]

  init() { rules = [] }

  init(rules: [RegexReplacementRule]) throws {
    guard rules.count <= Self.maximumRuleCount else {
      throw RegexReplacementRuleError.tooManyRules
    }
    self.rules = rules
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(rules: container.decode([RegexReplacementRule].self, forKey: .rules))
  }

  private enum CodingKeys: String, CodingKey {
    case rules
  }
}
