import Foundation

enum MathematicalNotationFormatter {
  static func format(_ input: String, as format: MathematicalNotationFormat) -> String {
    guard format != .plainText, isMathematical(input) else { return input }
    let tex = tex(from: input)
    return switch format {
    case .plainText: input
    case .latex: tex
    case .mathJax: "\\(\(tex)\\)"
    }
  }

  private static func isMathematical(_ input: String) -> Bool {
    input.range(
      of: #"\b(?:plus|minus|times|multiplied by|divided by|over|equals|equal to|squared|cubed|square root|to the power of|less than|greater than|alpha|beta|gamma|theta|pi)\b|[0-9=+*/^²³-]"#,
      options: [.regularExpression, .caseInsensitive]
    ) != nil
  }

  private static func tex(from input: String) -> String {
    var value = TextSanitizer.normalize(input)
    value = replacing(
      value,
      pattern: #"\b([[:alnum:]]+)\s+to\s+the\s+power\s+of\s+([[:alnum:]]+)\b"#,
      with: #"$1^{$2}"#
    )
    value = replacing(value, pattern: #"\b([[:alnum:]]+)\s+squared\b"#, with: #"$1^{2}"#)
    value = replacing(value, pattern: #"\b([[:alnum:]]+)\s+cubed\b"#, with: #"$1^{3}"#)
    value = replacing(
      value,
      pattern: #"\bsquare\s+root\s+of\s+([[:alnum:]]+)\b"#,
      with: #"\\sqrt{$1}"#
    )
    value = replacing(
      value,
      pattern: #"\b([[:alnum:]]+)\s+over\s+([[:alnum:]]+)\b"#,
      with: #"\\frac{$1}{$2}"#
    )
    for (pattern, replacement) in phraseReplacements {
      value = replacing(value, pattern: pattern, with: replacement)
    }
    for (pattern, replacement) in wordReplacements {
      value = replacing(value, pattern: pattern, with: replacement)
    }
    return value.replacingOccurrences(of: "²", with: "^{2}")
      .replacingOccurrences(of: "³", with: "^{3}")
  }

  private static func replacing(_ value: String, pattern: String, with replacement: String) -> String {
    value.replacingOccurrences(
      of: pattern,
      with: replacement,
      options: [.regularExpression, .caseInsensitive]
    )
  }

  private static let phraseReplacements = [
    (#"\bless\s+than\s+or\s+equal\s+to\b"#, #"\\le"#),
    (#"\bgreater\s+than\s+or\s+equal\s+to\b"#, #"\\ge"#),
    (#"\bnot\s+equal\s+to\b"#, #"\\ne"#),
    (#"\bmultiplied\s+by\b"#, #"\\times"#),
    (#"\bdivided\s+by\b"#, #"\\div"#),
    (#"\bequal\s+to\b"#, "="),
    (#"\bless\s+than\b"#, "<"),
    (#"\bgreater\s+than\b"#, ">"),
    (#"\bopen\s+parenthesis\b"#, "("),
    (#"\bclose\s+parenthesis\b"#, ")"),
  ]

  private static let wordReplacements = [
    (#"\bzero\b"#, "0"), (#"\bone\b"#, "1"), (#"\btwo\b"#, "2"),
    (#"\bthree\b"#, "3"), (#"\bfour\b"#, "4"), (#"\bfive\b"#, "5"),
    (#"\bsix\b"#, "6"), (#"\bseven\b"#, "7"), (#"\beight\b"#, "8"),
    (#"\bnine\b"#, "9"), (#"\bten\b"#, "10"), (#"\bplus\b"#, "+"),
    (#"\bminus\b"#, "-"), (#"\btimes\b"#, #"\\times"#), (#"\bequals\b"#, "="),
    (#"\balpha\b"#, #"\\alpha"#), (#"\bbeta\b"#, #"\\beta"#),
    (#"\bgamma\b"#, #"\\gamma"#), (#"\btheta\b"#, #"\\theta"#), (#"\bpi\b"#, #"\\pi"#),
  ]
}
