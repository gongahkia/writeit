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
  let allowsCloudOCR: Bool
  let customWords: CustomWordList

  init(
    imageData: Data,
    language: RecognitionLanguage,
    allowsCloudOCR: Bool = false,
    customWords: CustomWordList = CustomWordList(words: [])
  ) {
    self.imageData = imageData
    self.language = language
    self.allowsCloudOCR = allowsCloudOCR
    self.customWords = customWords
  }
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

struct ModelMacOSVersion: Codable, Sendable, Hashable, Comparable {
  let major: Int
  let minor: Int
  let patch: Int

  static let macOS15 = Self(major: 15, minor: 0, patch: 0)

  static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
  }
}

enum ModelAssetFormat: String, Codable, Sendable, Hashable {
  case file
  case zip
}

struct ModelManifest: Codable, Sendable, Hashable, Identifiable {
  let id: String
  let version: String
  let downloadURL: URL
  let sha256: String
  let license: String
  let supportedLanguages: Set<RecognitionLanguage>
  let requiresAppleSilicon: Bool
  let assetSizeBytes: UInt64
  let minimumMacOSVersion: ModelMacOSVersion
  let assetFormat: ModelAssetFormat

  init(
    id: String,
    version: String,
    downloadURL: URL,
    sha256: String,
    license: String,
    supportedLanguages: Set<RecognitionLanguage>,
    requiresAppleSilicon: Bool,
    assetSizeBytes: UInt64 = 0,
    minimumMacOSVersion: ModelMacOSVersion = .macOS15,
    assetFormat: ModelAssetFormat = .file
  ) {
    self.id = id
    self.version = version
    self.downloadURL = downloadURL
    self.sha256 = sha256
    self.license = license
    self.supportedLanguages = supportedLanguages
    self.requiresAppleSilicon = requiresAppleSilicon
    self.assetSizeBytes = assetSizeBytes
    self.minimumMacOSVersion = minimumMacOSVersion
    self.assetFormat = assetFormat
  }

  enum CodingKeys: String, CodingKey {
    case id, version, downloadURL, sha256, license, supportedLanguages, requiresAppleSilicon
    case assetSizeBytes, minimumMacOSVersion
    case assetFormat = "asset_format"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    version = try container.decode(String.self, forKey: .version)
    downloadURL = try container.decode(URL.self, forKey: .downloadURL)
    sha256 = try container.decode(String.self, forKey: .sha256)
    license = try container.decode(String.self, forKey: .license)
    supportedLanguages = try container.decode(Set<RecognitionLanguage>.self, forKey: .supportedLanguages)
    requiresAppleSilicon = try container.decode(Bool.self, forKey: .requiresAppleSilicon)
    assetSizeBytes = try container.decode(UInt64.self, forKey: .assetSizeBytes)
    minimumMacOSVersion = try container.decode(ModelMacOSVersion.self, forKey: .minimumMacOSVersion)
    assetFormat = try container.decodeIfPresent(ModelAssetFormat.self, forKey: .assetFormat) ?? .file
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(version, forKey: .version)
    try container.encode(downloadURL, forKey: .downloadURL)
    try container.encode(sha256, forKey: .sha256)
    try container.encode(license, forKey: .license)
    try container.encode(supportedLanguages, forKey: .supportedLanguages)
    try container.encode(requiresAppleSilicon, forKey: .requiresAppleSilicon)
    try container.encode(assetSizeBytes, forKey: .assetSizeBytes)
    try container.encode(minimumMacOSVersion, forKey: .minimumMacOSVersion)
    try container.encode(assetFormat, forKey: .assetFormat)
  }
}

enum ModelInstallationState: Sendable, Equatable {
  case notInstalled
  case downloading(progress: Double)
  case paused(progress: Double)
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
protocol DiagramTranslating: AnyObject {
  func translate(_ request: AIDiagramTranslationRequest) async throws -> AIDiagramTranslation?
}

@MainActor
struct DeliveryRequest {
  let text: String
  let target: TargetReference?
  let strategy: OutputStrategy
  let clipboardHandling: ClipboardHandling
  let verifyPaste: Bool
}

enum PasteDeliveryVerification: Equatable {
  case notRequested
  case verified
  case unavailable
  case failed
}

enum DeliveryFailure: Equatable {
  case targetUnavailable
  case targetNotEditable
  case targetAppNotRunning
  case activationFailed
  case activationTimedOut
  case accessibilityInsertionFailed
  case pasteEventUnavailable
  case clipboardWriteFailed

  var message: String {
    switch self {
    case .targetUnavailable: "Captured field is unavailable"
    case .targetNotEditable: "Captured field no longer accepts text"
    case .targetAppNotRunning: "Captured app is no longer running"
    case .activationFailed: "Couldn’t activate the captured app"
    case .activationTimedOut: "Captured app did not become active in time"
    case .accessibilityInsertionFailed: "Accessibility could not replace text in the captured field"
    case .pasteEventUnavailable: "WriteIt could not send the paste shortcut"
    case .clipboardWriteFailed: "WriteIt could not copy the result to the clipboard"
    }
  }
}

enum DeliveryOutcome: Equatable {
  case pasted(ClipboardHandling, PasteDeliveryVerification)
  case accessibilityInserted
  case clipboard
  case clipboardFallback(DeliveryFailure)
  case failed(DeliveryFailure)

  var message: String {
    switch self {
    case .pasted(_, .notRequested): "Pasted into captured field"
    case .pasted(_, .verified): "Pasted and verified in captured field"
    case .pasted(_, .unavailable): "Pasted; target could not verify insertion"
    case .pasted(_, .failed): "Paste sent; target did not verify insertion"
    case .accessibilityInserted: "Inserted into captured field"
    case .clipboard: "Copied to clipboard"
    case .clipboardFallback(let failure): "Copied: \(failure.message)"
    case .failed(let failure): failure.message
    }
  }

  var needsClipboardRecovery: Bool {
    if case .clipboardFallback = self { return true }
    return false
  }

  var failed: Bool {
    if case .failed = self { return true }
    return false
  }
}

@MainActor
protocol AccessibilityDelivering: AnyObject {
  var isTrusted: Bool { get }
  func requestTrust()
  func captureTarget() -> TargetReference?
  func clearCapturedTarget()
  func deliver(_ request: DeliveryRequest) async -> DeliveryOutcome
  func undo()
}

protocol GlobalShortcutMonitoring: AnyObject {
  func start(shortcut: Shortcut, handler: @escaping (CaptureCommand) -> Void)
  func stop()
}

protocol RecognitionBackend: Sendable {
  var capabilities: RecognitionBackendCapabilities { get }
  func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult
}

typealias TextRecognizing = RecognitionBackend

enum CloudCredentialValidation: Sendable, Equatable {
  case valid
  case invalidCredentials
  case notConfigured
  case unavailable
  case cancelled
}

protocol CloudCredentialValidating: Sendable {
  func validateCredentials() async -> CloudCredentialValidation
}

@MainActor
protocol TextEnhancing: AnyObject {
  func clean(_ request: TextEnhancementRequest) async throws -> String
  func saveAPIKey(_ value: String) throws
  func hasAPIKey() throws -> Bool
  func testConnection(baseURL: String, model: String) async -> AICleanupConnectionStatus
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
