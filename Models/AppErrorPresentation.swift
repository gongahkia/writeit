import Foundation

struct AppErrorPresentation: Identifiable, Equatable {
  enum Kind: Equatable {
    case accessibility
    case recognition
    case delivery
    case persistence
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
}
