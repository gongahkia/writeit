import Foundation

enum AICleanupTransportPolicy {
  static let timeoutInterval: TimeInterval = 30
  static let maximumAttempts = 2
  static let retryDelay: Duration = .milliseconds(250)

  static func shouldRetry(statusCode: Int) -> Bool {
    statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
  }

  static func shouldRetry(error: Error) -> Bool {
    guard let error = error as? URLError else { return false }
    return switch error.code {
    case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
      .cannotFindHost, .dnsLookupFailed:
      true
    default: false
    }
  }
}
