import Combine
import Foundation

final class Preferences: ObservableObject {
  @Published var shortcut: Shortcut { didSet { save(shortcut, key: "shortcut") } }
  @Published var captureMode: CaptureMode { didSet { save(captureMode, key: "captureMode") } }
  @Published var resultMode: ResultMode { didSet { save(resultMode, key: "resultMode") } }
  @Published var historyMode: HistoryMode { didSet { save(historyMode, key: "historyMode") } }
  @Published var historyAutoDelete: Bool { didSet { defaults.set(historyAutoDelete, forKey: "historyAutoDelete") } }
  @Published var historyRetentionDays: Int { didSet { defaults.set(historyRetentionDays, forKey: "historyRetentionDays") } }
  @Published var aiEnabled: Bool { didSet { defaults.set(aiEnabled, forKey: "aiEnabled") } }
  @Published var aiBaseURL: String { didSet { defaults.set(aiBaseURL, forKey: "aiBaseURL") } }
  @Published var aiModel: String { didSet { defaults.set(aiModel, forKey: "aiModel") } }
  @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }
  @Published var penUpDelay: Double { didSet { defaults.set(penUpDelay, forKey: "penUpDelay") } }

  private let defaults = UserDefaults.standard

  init() {
    shortcut = Self.load("shortcut", fallback: .default)
    captureMode = Self.load("captureMode", fallback: .toggle)
    resultMode = Self.load("resultMode", fallback: .autoInsert)
    historyMode = Self.load("historyMode", fallback: .full)
    historyAutoDelete = defaults.object(forKey: "historyAutoDelete") as? Bool ?? true
    historyRetentionDays = defaults.object(forKey: "historyRetentionDays") as? Int ?? 7
    aiEnabled = defaults.bool(forKey: "aiEnabled")
    aiBaseURL = defaults.string(forKey: "aiBaseURL") ?? "https://api.openai.com/v1/chat/completions"
    aiModel = defaults.string(forKey: "aiModel") ?? "gpt-4.1-mini"
    launchAtLogin = defaults.bool(forKey: "launchAtLogin")
    penUpDelay = defaults.object(forKey: "penUpDelay") as? Double ?? 1.2
  }

  private static func load<T: Codable>(_ key: String, fallback: T) -> T {
    guard let data = UserDefaults.standard.data(forKey: key), let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
    return value
  }

  private func save<T: Codable>(_ value: T, key: String) {
    defaults.set(try? JSONEncoder().encode(value), forKey: key)
  }
}
