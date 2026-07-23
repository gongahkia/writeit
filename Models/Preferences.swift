import Combine
import Foundation

final class Preferences: ObservableObject {
  static let currentSchemaVersion = 1

  @Published var shortcut: Shortcut { didSet { save(shortcut, key: .shortcut) } }
  @Published var captureMode: CaptureMode { didSet { save(captureMode, key: .captureMode) } }
  @Published var resultMode: ResultMode { didSet { save(resultMode, key: .resultMode) } }
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

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    Self.registerDefaults(in: defaults)
    Self.migrate(defaults)
    shortcut = Self.load(.shortcut, from: defaults, fallback: .default)
    captureMode = Self.load(.captureMode, from: defaults, fallback: .toggle)
    resultMode = Self.load(.resultMode, from: defaults, fallback: .autoInsert)
    historyMode = Self.load(.historyMode, from: defaults, fallback: .full)
    historyAutoDelete = defaults.bool(forKey: Key.historyAutoDelete.rawValue)
    historyRetentionDays = Self.validRetentionDays(
      defaults.integer(forKey: Key.historyRetentionDays.rawValue))
    aiEnabled = defaults.bool(forKey: Key.aiEnabled.rawValue)
    aiBaseURL = defaults.string(forKey: Key.aiBaseURL.rawValue) ?? Self.defaultAIBaseURL
    aiModel = defaults.string(forKey: Key.aiModel.rawValue) ?? Self.defaultAIModel
    launchAtLogin = defaults.bool(forKey: Key.launchAtLogin.rawValue)
    penUpDelay = Self.validPenUpDelay(defaults.double(forKey: Key.penUpDelay.rawValue))
  }

  private enum Key: String {
    case schemaVersion
    case shortcut
    case captureMode
    case resultMode
    case historyMode
    case historyAutoDelete
    case historyRetentionDays
    case aiEnabled
    case aiBaseURL
    case aiModel
    case launchAtLogin
    case penUpDelay
  }

  private static let defaultAIBaseURL = "https://api.openai.com/v1/chat/completions"
  private static let defaultAIModel = "gpt-4.1-mini"

  private static func registerDefaults(in defaults: UserDefaults) {
    defaults.register(defaults: [
      Key.schemaVersion.rawValue: 0,
      Key.historyAutoDelete.rawValue: true,
      Key.historyRetentionDays.rawValue: 7,
      Key.aiEnabled.rawValue: false,
      Key.aiBaseURL.rawValue: defaultAIBaseURL,
      Key.aiModel.rawValue: defaultAIModel,
      Key.launchAtLogin.rawValue: false,
      Key.penUpDelay.rawValue: 1.2,
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
    }
    defaults.set(currentSchemaVersion, forKey: Key.schemaVersion.rawValue)
  }

  private static func load<T: Codable>(_ key: Key, from defaults: UserDefaults, fallback: T) -> T {
    guard let data = defaults.data(forKey: key.rawValue),
      let value = try? JSONDecoder().decode(T.self, from: data)
    else { return fallback }
    return value
  }

  private func save<T: Codable>(_ value: T, key: Key) {
    defaults.set(try? JSONEncoder().encode(value), forKey: key.rawValue)
  }

  private static func validRetentionDays(_ value: Int) -> Int { min(max(value, 1), 365) }
  private static func validPenUpDelay(_ value: Double) -> Double { min(max(value, 0.5), 3) }
}
