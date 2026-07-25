import Combine
import Foundation

enum PreferenceStoreError: LocalizedError, Equatable {
  case invalidStoredValue
  case serializationFailed

  var errorDescription: String? {
    switch self {
    case .invalidStoredValue: "Some saved settings could not be read and were reset."
    case .serializationFailed: "WriteIt could not save this setting."
    }
  }
}

final class Preferences: ObservableObject {
  static let currentSchemaVersion = 4

  @Published var shortcut: Shortcut { didSet { save(shortcut, key: .shortcut) } }
  @Published var captureMode: CaptureMode { didSet { save(captureMode, key: .captureMode) } }
  @Published var resultMode: ResultMode { didSet { save(resultMode, key: .resultMode) } }
  @Published var outputStrategy: OutputStrategy {
    didSet { save(outputStrategy, key: .outputStrategy) }
  }
  @Published var clipboardHandling: ClipboardHandling {
    didSet { save(clipboardHandling, key: .clipboardHandling) }
  }
  @Published var verifyPasteDelivery: Bool {
    didSet { defaults.set(verifyPasteDelivery, forKey: Key.verifyPasteDelivery.rawValue) }
  }
  @Published var recognitionLanguage: RecognitionLanguage {
    didSet { save(recognitionLanguage, key: .recognitionLanguage) }
  }
  @Published var customWords: CustomWordList {
    didSet { save(customWords, key: .customWords) }
  }
  @Published var historyMode: HistoryMode { didSet { save(historyMode, key: .historyMode) } }
  @Published var historyAutoDelete: Bool {
    didSet { defaults.set(historyAutoDelete, forKey: Key.historyAutoDelete.rawValue) }
  }
  @Published var historyRetentionDays: Int {
    didSet {
      defaults.set(
        Self.validRetentionDays(historyRetentionDays), forKey: Key.historyRetentionDays.rawValue)
    }
  }
  @Published var aiEnabled: Bool {
    didSet { defaults.set(aiEnabled, forKey: Key.aiEnabled.rawValue) }
  }
  @Published var aiBaseURL: String {
    didSet { defaults.set(aiBaseURL, forKey: Key.aiBaseURL.rawValue) }
  }
  @Published var aiModel: String { didSet { defaults.set(aiModel, forKey: Key.aiModel.rawValue) } }
  @Published var launchAtLogin: Bool {
    didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin.rawValue) }
  }
  @Published var penUpDelay: Double {
    didSet { defaults.set(Self.validPenUpDelay(penUpDelay), forKey: Key.penUpDelay.rawValue) }
  }
  @Published var strokeWidth: Double {
    didSet { defaults.set(Self.validStrokeWidth(strokeWidth), forKey: Key.strokeWidth.rawValue) }
  }
  @Published var pressureSensitivity: Double {
    didSet {
      defaults.set(
        Self.validUnitInterval(pressureSensitivity),
        forKey: Key.pressureSensitivity.rawValue
      )
    }
  }
  @Published var strokeSmoothing: Double {
    didSet {
      defaults.set(Self.validUnitInterval(strokeSmoothing), forKey: Key.strokeSmoothing.rawValue)
    }
  }
  @Published private(set) var error: AppErrorPresentation?

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    Self.registerDefaults(in: defaults)
    Self.migrate(defaults)
    let shortcutResult = Self.load(.shortcut, from: defaults, fallback: Shortcut.default)
    let captureModeResult = Self.load(.captureMode, from: defaults, fallback: CaptureMode.toggle)
    let resultModeResult = Self.load(.resultMode, from: defaults, fallback: ResultMode.autoInsert)
    let outputStrategyResult = Self.load(
      .outputStrategy, from: defaults, fallback: OutputStrategy.paste)
    let clipboardHandlingResult = Self.load(
      .clipboardHandling, from: defaults, fallback: ClipboardHandling.restorePrevious)
    let recognitionLanguageResult = Self.load(
      .recognitionLanguage, from: defaults, fallback: RecognitionLanguage.english)
    let customWordsResult = Self.load(
      .customWords, from: defaults, fallback: CustomWordList(words: []))
    let historyModeResult = Self.load(.historyMode, from: defaults, fallback: HistoryMode.textOnly)
    shortcut = shortcutResult.value
    captureMode = captureModeResult.value
    resultMode = resultModeResult.value
    outputStrategy = outputStrategyResult.value
    clipboardHandling = clipboardHandlingResult.value
    verifyPasteDelivery = defaults.bool(forKey: Key.verifyPasteDelivery.rawValue)
    recognitionLanguage = recognitionLanguageResult.value
    customWords = customWordsResult.value
    historyMode = historyModeResult.value
    historyAutoDelete = defaults.bool(forKey: Key.historyAutoDelete.rawValue)
    historyRetentionDays = Self.validRetentionDays(
      defaults.integer(forKey: Key.historyRetentionDays.rawValue))
    aiEnabled = defaults.bool(forKey: Key.aiEnabled.rawValue)
    aiBaseURL = defaults.string(forKey: Key.aiBaseURL.rawValue) ?? Self.defaultAIBaseURL
    aiModel = defaults.string(forKey: Key.aiModel.rawValue) ?? Self.defaultAIModel
    launchAtLogin = defaults.bool(forKey: Key.launchAtLogin.rawValue)
    penUpDelay = Self.validPenUpDelay(defaults.double(forKey: Key.penUpDelay.rawValue))
    strokeWidth = Self.validStrokeWidth(defaults.double(forKey: Key.strokeWidth.rawValue))
    pressureSensitivity = Self.validUnitInterval(
      defaults.double(forKey: Key.pressureSensitivity.rawValue))
    strokeSmoothing = Self.validUnitInterval(defaults.double(forKey: Key.strokeSmoothing.rawValue))
    error = [
      shortcutResult.error,
      captureModeResult.error,
      resultModeResult.error,
      outputStrategyResult.error,
      clipboardHandlingResult.error,
      recognitionLanguageResult.error,
      customWordsResult.error,
      historyModeResult.error,
    ].compactMap { $0 }.first.map(AppErrorPresentation.persistence)
  }

  var inkStyle: InkStyle {
    InkStyle(
      baseWidth: strokeWidth,
      pressureSensitivity: pressureSensitivity,
      smoothing: strokeSmoothing
    )
  }

  private enum Key: String {
    case schemaVersion
    case shortcut
    case captureMode
    case resultMode
    case outputStrategy
    case clipboardHandling
    case verifyPasteDelivery
    case recognitionLanguage
    case customWords
    case historyMode
    case historyAutoDelete
    case historyRetentionDays
    case aiEnabled
    case aiBaseURL
    case aiModel
    case launchAtLogin
    case penUpDelay
    case strokeWidth
    case pressureSensitivity
    case strokeSmoothing
  }

  private static let defaultAIBaseURL = "https://api.openai.com/v1/chat/completions"
  private static let defaultAIModel = "gpt-4.1-mini"

  private static func registerDefaults(in defaults: UserDefaults) {
    defaults.register(defaults: [
      Key.schemaVersion.rawValue: 0,
      Key.historyAutoDelete.rawValue: true,
      Key.verifyPasteDelivery.rawValue: false,
      Key.historyRetentionDays.rawValue: 7,
      Key.aiEnabled.rawValue: false,
      Key.aiBaseURL.rawValue: defaultAIBaseURL,
      Key.aiModel.rawValue: defaultAIModel,
      Key.launchAtLogin.rawValue: false,
      Key.penUpDelay.rawValue: 1.2,
      Key.strokeWidth.rawValue: InkStyle.default.baseWidth,
      Key.pressureSensitivity.rawValue: InkStyle.default.pressureSensitivity,
      Key.strokeSmoothing.rawValue: InkStyle.default.smoothing,
    ])
  }

  private static func migrate(_ defaults: UserDefaults) {
    let version = defaults.integer(forKey: Key.schemaVersion.rawValue)
    if version < 1 {
      defaults.set(
        validRetentionDays(defaults.integer(forKey: Key.historyRetentionDays.rawValue)),
        forKey: Key.historyRetentionDays.rawValue)
      defaults.set(
        validPenUpDelay(defaults.double(forKey: Key.penUpDelay.rawValue)),
        forKey: Key.penUpDelay.rawValue)
      defaults.set(
        validStrokeWidth(defaults.double(forKey: Key.strokeWidth.rawValue)),
        forKey: Key.strokeWidth.rawValue)
      defaults.set(
        validUnitInterval(defaults.double(forKey: Key.pressureSensitivity.rawValue)),
        forKey: Key.pressureSensitivity.rawValue)
      defaults.set(
        validUnitInterval(defaults.double(forKey: Key.strokeSmoothing.rawValue)),
        forKey: Key.strokeSmoothing.rawValue)
    }
    defaults.set(currentSchemaVersion, forKey: Key.schemaVersion.rawValue)
  }

  func clearError() { error = nil }

  private static func load<T: Codable>(
    _ key: Key,
    from defaults: UserDefaults,
    fallback: T
  ) -> (value: T, error: PreferenceStoreError?) {
    guard let data = defaults.data(forKey: key.rawValue) else { return (fallback, nil) }
    do {
      return (try JSONDecoder().decode(T.self, from: data), nil)
    } catch {
      defaults.removeObject(forKey: key.rawValue)
      return (fallback, .invalidStoredValue)
    }
  }

  private func save<T: Codable>(_ value: T, key: Key) {
    do {
      defaults.set(try JSONEncoder().encode(value), forKey: key.rawValue)
      error = nil
    } catch {
      AppLog.app.error(
        "preferences_save_failed type=\(AppLog.errorType(error), privacy: .public)")
      self.error = .persistence(PreferenceStoreError.serializationFailed)
    }
  }

  private static func validRetentionDays(_ value: Int) -> Int { min(max(value, 1), 365) }
  private static func validPenUpDelay(_ value: Double) -> Double { min(max(value, 0.5), 3) }
  private static func validStrokeWidth(_ value: Double) -> Double { min(max(value, 1), 12) }
  private static func validUnitInterval(_ value: Double) -> Double { min(max(value, 0), 1) }
}
