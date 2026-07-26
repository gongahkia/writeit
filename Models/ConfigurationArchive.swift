import Foundation

enum ConfigurationArchiveError: LocalizedError, Equatable {
  case invalidArchive
  case invalidConfiguration
  case rollbackFailed
  case unreadableFile
  case unsupportedVersion
  case unwritableFile

  var errorDescription: String? {
    switch self {
    case .invalidArchive: "Configuration file is invalid."
    case .invalidConfiguration: "Configuration values are invalid."
    case .rollbackFailed: "Configuration import could not be rolled back."
    case .unreadableFile: "Configuration file could not be read."
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
  let mathematicalNotationFormat: MathematicalNotationFormat
  let flowchartDirection: FlowchartDirection
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
    mathematicalNotationFormat = preferences.mathematicalNotationFormat
    flowchartDirection = preferences.flowchartDirection
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

  func validated() throws {
    guard ShortcutConflictValidator.message(for: shortcut) == nil,
      recognitionBackendID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
      (1...365).contains(historyRetentionDays),
      (0.5...3).contains(penUpDelay),
      (1...12).contains(strokeWidth),
      (0...1).contains(pressureSensitivity),
      (0...1).contains(strokeSmoothing)
    else { throw ConfigurationArchiveError.invalidConfiguration }
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    shortcut = try container.decode(Shortcut.self, forKey: .shortcut)
    captureMode = try container.decode(CaptureMode.self, forKey: .captureMode)
    resultMode = try container.decode(ResultMode.self, forKey: .resultMode)
    outputStrategy = try container.decode(OutputStrategy.self, forKey: .outputStrategy)
    clipboardHandling = try container.decode(ClipboardHandling.self, forKey: .clipboardHandling)
    verifyPasteDelivery = try container.decode(Bool.self, forKey: .verifyPasteDelivery)
    recognitionLanguage = try container.decode(RecognitionLanguage.self, forKey: .recognitionLanguage)
    recognitionBackendID = try container.decode(String.self, forKey: .recognitionBackendID)
    customWords = try container.decode(CustomWordList.self, forKey: .customWords)
    literalReplacementRules = try container.decode(
      LiteralReplacementRules.self, forKey: .literalReplacementRules)
    regexReplacementRules = try container.decode(
      RegexReplacementRules.self, forKey: .regexReplacementRules)
    mathematicalNotationFormat = try container.decodeIfPresent(
      MathematicalNotationFormat.self, forKey: .mathematicalNotationFormat) ?? .plainText
    flowchartDirection = try container.decodeIfPresent(
      FlowchartDirection.self, forKey: .flowchartDirection) ?? .leftToRight
    historyMode = try container.decode(HistoryMode.self, forKey: .historyMode)
    historyAutoDelete = try container.decode(Bool.self, forKey: .historyAutoDelete)
    historyRetentionDays = try container.decode(Int.self, forKey: .historyRetentionDays)
    aiEnabled = try container.decode(Bool.self, forKey: .aiEnabled)
    aiBaseURL = try container.decode(String.self, forKey: .aiBaseURL)
    aiModel = try container.decode(String.self, forKey: .aiModel)
    launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
    penUpDelay = try container.decode(Double.self, forKey: .penUpDelay)
    strokeWidth = try container.decode(Double.self, forKey: .strokeWidth)
    pressureSensitivity = try container.decode(Double.self, forKey: .pressureSensitivity)
    strokeSmoothing = try container.decode(Double.self, forKey: .strokeSmoothing)
  }

  private enum CodingKeys: String, CodingKey {
    case shortcut
    case captureMode
    case resultMode
    case outputStrategy
    case clipboardHandling
    case verifyPasteDelivery
    case recognitionLanguage
    case recognitionBackendID
    case customWords
    case literalReplacementRules
    case regexReplacementRules
    case mathematicalNotationFormat
    case flowchartDirection
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
}

struct ConfigurationCloudOCRProvider: Codable, Equatable {
  let provider: CloudOCRProvider
  let endpoint: URL?

  init(configuration: CloudOCRProviderConfiguration) {
    provider = configuration.provider
    endpoint = configuration.endpoint
  }

  func validated() throws {
    switch provider {
    case .googleVision:
      guard endpoint == nil else { throw ConfigurationArchiveError.invalidConfiguration }
    case .azureVision:
      guard let endpoint, AzureVisionRecognitionService.isAzureEndpoint(endpoint) else {
        throw ConfigurationArchiveError.invalidConfiguration
      }
    }
  }
}

struct ConfigurationArchive: Codable, Equatable {
  static let currentSchemaVersion = 3

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
    guard (1...Self.currentSchemaVersion).contains(schemaVersion)
    else { throw ConfigurationArchiveError.unsupportedVersion }
    self.schemaVersion = schemaVersion
    preferences = try container.decode(ConfigurationPreferences.self, forKey: .preferences)
    profiles = try container.decode([AppProfile].self, forKey: .profiles)
    cloudOCRProviders = try container.decode(
      [ConfigurationCloudOCRProvider].self, forKey: .cloudOCRProviders)
  }

  func validated() throws {
    try preferences.validated()
    guard Set(cloudOCRProviders.map(\.provider)).count == cloudOCRProviders.count else {
      throw ConfigurationArchiveError.invalidConfiguration
    }
    try cloudOCRProviders.forEach { try $0.validated() }
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

  static func decode(_ data: Data) throws -> ConfigurationArchive {
    do {
      let archive = try JSONDecoder().decode(ConfigurationArchive.self, from: data)
      try archive.validated()
      return archive
    } catch let error as ConfigurationArchiveError {
      throw error
    } catch {
      throw ConfigurationArchiveError.invalidArchive
    }
  }
}

enum ConfigurationArchiveFileStore {
  static func read(from url: URL) throws -> Data {
    do {
      return try Data(contentsOf: url)
    } catch {
      throw ConfigurationArchiveError.unreadableFile
    }
  }

  static func write(_ data: Data, to url: URL) throws {
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      throw ConfigurationArchiveError.unwritableFile
    }
  }
}
