import AppKit
import Foundation

enum RecognitionLanguage: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
  case english = "en-US"
  case french = "fr-FR"
  case german = "de-DE"
  case spanish = "es-ES"
  case italian = "it-IT"
  case portuguese = "pt-PT"

  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .english: "English"
    case .french: "French"
    case .german: "German"
    case .spanish: "Spanish"
    case .italian: "Italian"
    case .portuguese: "Portuguese"
    }
  }
}

struct RecognitionRequest: Sendable {
  let imageData: Data
  let language: RecognitionLanguage
}

struct RecognitionResult: Equatable, Sendable {
  let text: String
  let confidence: Float
  let backendID: String
  let languageResolution: RecognitionLanguageResolution

  init(
    text: String,
    confidence: Float,
    backendID: String,
    languageResolution: RecognitionLanguageResolution = .identity(.english)
  ) {
    self.text = text
    self.confidence = confidence
    self.backendID = backendID
    self.languageResolution = languageResolution
  }
}

struct RecognitionLanguageResolution: Equatable, Sendable {
  let requested: RecognitionLanguage
  let resolved: RecognitionLanguage

  var usedFallback: Bool { requested != resolved }

  static func identity(_ language: RecognitionLanguage) -> Self {
    Self(requested: language, resolved: language)
  }
}

struct RecognitionBackendCapabilities: Sendable, Equatable {
  let identifier: String
  let displayName: String
  let supportedLanguages: Set<RecognitionLanguage>
  let isLocal: Bool
  let supportsStreaming: Bool
  let availability: RecognitionBackendAvailability

  func supports(_ language: RecognitionLanguage) -> Bool {
    supportedLanguages.contains(language)
  }

  func resolve(_ requested: RecognitionLanguage) -> RecognitionLanguageResolution? {
    if supports(requested) { return .identity(requested) }
    guard supports(.english) else { return nil }
    return RecognitionLanguageResolution(requested: requested, resolved: .english)
  }
}

enum RecognitionBackendAvailability: Sendable, Equatable {
  case available
  case unavailable(String)
}

struct ModelManifest: Codable, Sendable, Hashable, Identifiable {
  let id: String
  let version: String
  let downloadURL: URL
  let sha256: String
  let license: String
  let supportedLanguages: Set<RecognitionLanguage>
  let requiresAppleSilicon: Bool
}

enum ModelInstallationState: Sendable, Equatable {
  case notInstalled
  case downloading(progress: Double)
  case installed(URL)
  case failed(String)
}

enum RecognitionError: LocalizedError, Sendable {
  case invalidImage
  case noText
  case unavailable(String)
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .invalidImage: "WriteIt could not read the captured ink."
    case .noText: "No handwriting was recognized."
    case .unavailable(let message), .failed(let message): message
    }
  }
}

struct TextEnhancementRequest: Sendable {
  let text: String
  let enabled: Bool
  let baseURL: String
  let model: String
}

@MainActor
struct DeliveryRequest {
  let text: String
  let target: TargetReference?
  let strategy: OutputStrategy
  let clipboardHandling: ClipboardHandling
}

enum DeliveryFailure: Equatable {
  case targetUnavailable
  case targetNotEditable
  case targetAppNotRunning
  case activationFailed
  case accessibilityInsertionFailed
  case pasteEventUnavailable
  case clipboardWriteFailed

  var message: String {
    switch self {
    case .targetUnavailable: "Captured field is unavailable"
    case .targetNotEditable: "Captured field no longer accepts text"
    case .targetAppNotRunning: "Captured app is no longer running"
    case .activationFailed: "Couldn’t activate the captured app"
    case .accessibilityInsertionFailed: "Accessibility could not replace text in the captured field"
    case .pasteEventUnavailable: "WriteIt could not send the paste shortcut"
    case .clipboardWriteFailed: "WriteIt could not copy the result to the clipboard"
    }
  }
}

enum DeliveryOutcome: Equatable {
  case pasted(ClipboardHandling)
  case accessibilityInserted
  case clipboard
  case clipboardFallback(DeliveryFailure)
  case failed(DeliveryFailure)

  var message: String {
    switch self {
    case .pasted: "Pasted into captured field"
    case .accessibilityInserted: "Inserted into captured field"
    case .clipboard: "Copied to clipboard"
    case .clipboardFallback(let failure): "Copied: \(failure.message)"
    case .failed(let failure): failure.message
    }
  }
}

@MainActor
protocol AccessibilityDelivering: AnyObject {
  var isTrusted: Bool { get }
  func requestTrust()
  func captureTarget() -> TargetReference?
  func deliver(_ request: DeliveryRequest) -> DeliveryOutcome
  func undo()
}

protocol GlobalShortcutMonitoring: AnyObject {
  func start(shortcut: Shortcut, handler: @escaping (ShortcutEvent) -> Void)
  func stop()
}

protocol RecognitionBackend: Sendable {
  var capabilities: RecognitionBackendCapabilities { get }
  func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult
}

typealias TextRecognizing = RecognitionBackend

@MainActor
protocol TextEnhancing: AnyObject {
  func clean(_ request: TextEnhancementRequest) async throws -> String
  func saveAPIKey(_ value: String) throws
  func hasAPIKey() throws -> Bool
}

@MainActor
protocol CaptureOverlayPresenting: AnyObject {
  func present(session: CaptureSession, coordinator: CaptureCoordinator, preferences: Preferences)
  func dismiss()
}

@MainActor
protocol LoginItemManaging: AnyObject {
  func update(enabled: Bool)
}
