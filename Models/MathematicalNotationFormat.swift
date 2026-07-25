import Foundation

enum MathematicalNotationFormat: String, CaseIterable, Codable, Identifiable, Sendable {
  case plainText
  case latex
  case mathJax

  var id: String { rawValue }
  var title: String {
    switch self {
    case .plainText: "Plain text"
    case .latex: "LaTeX"
    case .mathJax: "MathJax"
    }
  }
}
