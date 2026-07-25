import Foundation

struct CustomWordList: Codable, Sendable, Equatable {
  let words: [String]

  init(words: [String]) {
    var seen: Set<String> = []
    self.words = words.compactMap { word in
      let normalized = word.precomposedStringWithCanonicalMapping.trimmingCharacters(
        in: .whitespacesAndNewlines)
      guard normalized.isEmpty == false, seen.insert(normalized.lowercased()).inserted else {
        return nil
      }
      return normalized
    }
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(words: try container.decode([String].self, forKey: .words))
  }

  private enum CodingKeys: String, CodingKey {
    case words
  }
}
