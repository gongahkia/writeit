import Foundation

enum ConfigurationArchiveError: LocalizedError, Equatable {
  case invalidArchive
  case unsupportedVersion
  case unwritableFile

  var errorDescription: String? {
    switch self {
    case .invalidArchive: "Configuration file is invalid."
    case .unsupportedVersion: "Configuration file uses an unsupported version."
    case .unwritableFile: "Configuration file could not be saved."
    }
  }
}

struct ConfigurationPreferences: Codable, Equatable {
  let shortcut: Shortcut
  let captureMode: CaptureMode
  let resultMode: ResultMode
  let outputStrategy: OutputStrategy
  let clipboardHandling: ClipboardHandling
  let verifyPasteDelivery: Bool
  let recognitionLanguage: RecognitionLanguage
  let recognitionBackendID: String
  let customWords: CustomWordList
  let literalReplacementRules: LiteralReplacementRules
  let regexReplacementRules: RegexReplacementRules
  let historyMode: HistoryMode
  let historyAutoDelete: Bool
  let historyRetentionDays: Int
  let aiEnabled: Bool
  let aiBaseURL: String
  let aiModel: String
  let launchAtLogin: Bool
  let penUpDelay: Double
  let strokeWidth: Double
  let pressureSensitivity: Double
  let strokeSmoothing: Double

  init(preferences: Preferences) {
    shortcut = preferences.shortcut
    captureMode = preferences.captureMode
    resultMode = preferences.resultMode
    outputStrategy = preferences.outputStrategy
    clipboardHandling = preferences.clipboardHandling
    verifyPasteDelivery = preferences.verifyPasteDelivery
    recognitionLanguage = preferences.recognitionLanguage
    recognitionBackendID = preferences.recognitionBackendID
    customWords = preferences.customWords
    literalReplacementRules = preferences.literalReplacementRules
    regexReplacementRules = preferences.regexReplacementRules
    historyMode = preferences.historyMode
    historyAutoDelete = preferences.historyAutoDelete
    historyRetentionDays = preferences.historyRetentionDays
    aiEnabled = preferences.aiEnabled
    aiBaseURL = preferences.aiBaseURL
    aiModel = preferences.aiModel
    launchAtLogin = preferences.launchAtLogin
    penUpDelay = preferences.penUpDelay
    strokeWidth = preferences.strokeWidth
    pressureSensitivity = preferences.pressureSensitivity
    strokeSmoothing = preferences.strokeSmoothing
  }
}

struct ConfigurationCloudOCRProvider: Codable, Equatable {
  let provider: CloudOCRProvider
  let endpoint: URL?

  init(configuration: CloudOCRProviderConfiguration) {
    provider = configuration.provider
    endpoint = configuration.endpoint
  }
}

struct ConfigurationArchive: Codable, Equatable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let preferences: ConfigurationPreferences
  let profiles: [AppProfile]
  let cloudOCRProviders: [ConfigurationCloudOCRProvider]

  init(
    preferences: Preferences,
    profiles: [AppProfile],
    cloudOCRProviders: [CloudOCRProviderConfiguration]
  ) {
    schemaVersion = Self.currentSchemaVersion
    self.preferences = ConfigurationPreferences(preferences: preferences)
    self.profiles = profiles
    self.cloudOCRProviders = cloudOCRProviders.map(ConfigurationCloudOCRProvider.init)
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard Set(container.allKeys).isSubset(of: Set(CodingKeys.allCases))
    else { throw ConfigurationArchiveError.invalidArchive }
    let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    guard schemaVersion == Self.currentSchemaVersion
    else { throw ConfigurationArchiveError.unsupportedVersion }
    self.schemaVersion = schemaVersion
    preferences = try container.decode(ConfigurationPreferences.self, forKey: .preferences)
    profiles = try container.decode([AppProfile].self, forKey: .profiles)
    cloudOCRProviders = try container.decode(
      [ConfigurationCloudOCRProvider].self, forKey: .cloudOCRProviders)
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion = "schema_version"
    case preferences
    case profiles
    case cloudOCRProviders = "cloud_ocr_providers"
  }
}

enum ConfigurationArchiveCodec {
  static func encode(_ archive: ConfigurationArchive) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(archive)
  }
}

enum ConfigurationArchiveFileStore {
  static func write(_ data: Data, to url: URL) throws {
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      throw ConfigurationArchiveError.unwritableFile
    }
  }
}
