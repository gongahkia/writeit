import Foundation

struct AppErrorPresentation: Identifiable, Equatable {
  enum Kind: Equatable {
    case accessibility
    case recognition
    case delivery
    case persistence
    case security
    case configuration
  }

  let id = UUID()
  let kind: Kind
  let title: String
  let message: String

  static func recognition(_ error: Error) -> Self {
    let message = (error as? LocalizedError)?.errorDescription ?? "Recognition failed."
    return Self(kind: .recognition, title: "Couldn’t read handwriting", message: message)
  }

  static func captureInput(_ message: String) -> Self {
    Self(kind: .configuration, title: "Add more ink", message: message)
  }

  static func delivery(_ outcome: DeliveryOutcome) -> Self? {
    switch outcome {
    case .clipboardFallback(let failure):
      return Self(
        kind: .delivery,
        title: "Copied to clipboard",
        message: "\(failure.message). Your recognized text is available in the clipboard."
      )
    case .failed(let failure):
      return Self(kind: .delivery, title: "Couldn’t deliver text", message: failure.message)
    case .pasted, .accessibilityInserted, .clipboard: return nil
    }
  }

  static func persistence(_ error: Error) -> Self {
    let message = (error as? LocalizedError)?.errorDescription ?? "WriteIt could not update local data."
    return Self(kind: .persistence, title: "Local data unavailable", message: message)
  }

  static func security(_ error: Error) -> Self {
    let message = (error as? LocalizedError)?.errorDescription ?? "WriteIt could not access secure storage."
    return Self(kind: .security, title: "Keychain unavailable", message: message)
  }
}
