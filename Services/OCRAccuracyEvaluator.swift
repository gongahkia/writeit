import Foundation

enum OCRAccuracyEvaluator {
  static func characterErrorRate(expected: String, actual: String) -> Double {
    rate(expected: Array(expected), actual: Array(actual))
  }

  static func wordErrorRate(expected: String, actual: String) -> Double {
    let expectedWords = TextSanitizer.normalize(expected).split(separator: " ").map(String.init)
    let actualWords = TextSanitizer.normalize(actual).split(separator: " ").map(String.init)
    return rate(expected: expectedWords, actual: actualWords)
  }

  private static func rate<Element: Equatable>(expected: [Element], actual: [Element]) -> Double {
    if expected.isEmpty { return actual.isEmpty ? 0 : 1 }
    return Double(editDistance(expected: expected, actual: actual)) / Double(expected.count)
  }

  private static func editDistance<Element: Equatable>(expected: [Element], actual: [Element]) -> Int {
    var previous = Array(0...actual.count)
    for (expectedIndex, expectedValue) in expected.enumerated() {
      var current = [expectedIndex + 1]
      for (actualIndex, actualValue) in actual.enumerated() {
        current.append(
          min(
            previous[actualIndex + 1] + 1,
            current[actualIndex] + 1,
            previous[actualIndex] + (expectedValue == actualValue ? 0 : 1)
          )
        )
      }
      previous = current
    }
    return previous[actual.count]
  }
}
