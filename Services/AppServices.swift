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
protocol AccessibilityDelivering: AnyObject {
  var isTrusted: Bool { get }
  func requestTrust()
  func captureTarget() -> TargetReference?
  func deliver(_ text: String, to target: TargetReference?, strategy: OutputStrategy)
    -> DeliveryOutcome
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
  func saveAPIKey(_ value: String)
  func hasAPIKey() -> Bool
}

@MainActor
protocol CaptureOverlayPresenting: AnyObject {
  func present(session: CaptureSession, model: AppModel)
  func dismiss()
}

@MainActor
protocol LoginItemManaging: AnyObject {
  func update(enabled: Bool)
}
