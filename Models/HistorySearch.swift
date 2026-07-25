import Foundation

enum HistorySearch {
  static func matches(text: String, query: String, locale: Locale = .current) -> Bool {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.isEmpty == false else { return true }
    return text.range(
      of: query,
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: locale
    ) != nil
  }
}
