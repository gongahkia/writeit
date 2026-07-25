import Combine
import Foundation

enum CloudOCRProvider: String, CaseIterable, Codable, Sendable, Identifiable {
  case googleVision = "google-cloud-vision"
  case azureVision = "azure-ai-vision-read"

  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .googleVision: "Google Cloud Vision"
    case .azureVision: "Azure AI Vision Read"
    }
  }
  var credentialAccount: String { "ocr-provider.\(rawValue).api-key" }
  var capabilities: RecognitionBackendCapabilities {
    RecognitionBackendCapabilities(
      identifier: rawValue,
      displayName: displayName,
      supportedLanguages: Set(RecognitionLanguage.allCases),
      isLocal: false,
      supportsStreaming: false,
      availability: .available
    )
  }
}

struct CloudOCRProviderConfiguration: Codable, Sendable, Equatable, Identifiable {
  let provider: CloudOCRProvider
  let endpoint: URL?
  let isValidated: Bool

  var id: CloudOCRProvider { provider }

  init(provider: CloudOCRProvider, endpoint: URL? = nil, isValidated: Bool = false) {
    self.provider = provider
    self.endpoint = endpoint
    self.isValidated = isValidated
  }

  func settingValidated(_ isValidated: Bool) -> Self {
    Self(provider: provider, endpoint: endpoint, isValidated: isValidated)
  }
}

enum CloudOCRProviderStoreError: LocalizedError, Equatable {
  case invalidAPIKey
  case invalidAzureEndpoint
  case unreadableArchive
  case serializationFailed

  var errorDescription: String? {
    switch self {
    case .invalidAPIKey: "An API key is required."
    case .invalidAzureEndpoint:
      "Azure AI Vision requires an HTTPS Cognitive Services endpoint."
    case .unreadableArchive: "Saved cloud OCR configuration could not be read."
    case .serializationFailed: "WriteIt could not save cloud OCR configuration."
    }
  }
}

@MainActor
protocol CloudOCRCredentialStoring: AnyObject {
  func data(for account: String) throws -> Data?
  func set(_ data: Data, for account: String) throws
  func delete(_ account: String) throws
}

@MainActor
final class KeychainCloudOCRCredentialStore: CloudOCRCredentialStoring {
  func data(for account: String) throws -> Data? { try KeychainStore.data(for: account) }
  func set(_ data: Data, for account: String) throws { try KeychainStore.set(data, for: account) }
  func delete(_ account: String) throws { try KeychainStore.delete(account) }
}

protocol CloudOCRProviderTesting: Sendable {
  func validate(
    provider: CloudOCRProvider,
    endpoint: URL?,
    apiKey: String
  ) async -> CloudCredentialValidation
}

struct LiveCloudOCRProviderTester: CloudOCRProviderTesting {
  func validate(
    provider: CloudOCRProvider,
    endpoint: URL?,
    apiKey: String
  ) async -> CloudCredentialValidation {
    switch provider {
    case .googleVision:
      return await GoogleVisionRecognitionService(apiKey: apiKey).validateCredentials()
    case .azureVision:
      guard let endpoint else { return .notConfigured }
      return await AzureVisionRecognitionService(endpoint: endpoint, apiKey: apiKey)
        .validateCredentials()
    }
  }
}

@MainActor
final class CloudOCRProviderStore: ObservableObject {
  nonisolated static let archiveDefaultsKey = "cloudOCRProviders.archive"
  nonisolated static let schemaVersionDefaultsKey = "cloudOCRProviders.schemaVersion"
  nonisolated static let currentSchemaVersion = 1

  @Published private(set) var configurations: [CloudOCRProviderConfiguration]
  @Published private(set) var validationStatuses: [CloudOCRProvider: CloudCredentialValidation]
  @Published private(set) var error: AppErrorPresentation?

  private let defaults: UserDefaults
  private let credentials: any CloudOCRCredentialStoring
  private let tester: any CloudOCRProviderTesting

  init(
    defaults: UserDefaults = .standard,
    credentials: any CloudOCRCredentialStoring = KeychainCloudOCRCredentialStore(),
    tester: any CloudOCRProviderTesting = LiveCloudOCRProviderTester()
  ) {
    self.defaults = defaults
    self.credentials = credentials
    self.tester = tester
    let result = Self.load(defaults: defaults)
    configurations = result.configurations
    validationStatuses = Dictionary(
      uniqueKeysWithValues: result.configurations.compactMap { configuration in
        configuration.isValidated ? (configuration.provider, .valid) : nil
      }
    )
    error = result.error.map(AppErrorPresentation.persistence)
  }

  func configuration(for provider: CloudOCRProvider) -> CloudOCRProviderConfiguration? {
    configurations.first { $0.provider == provider }
  }

  func validationStatus(for provider: CloudOCRProvider) -> CloudCredentialValidation? {
    validationStatuses[provider]
  }

  func isSelectable(_ provider: CloudOCRProvider) -> Bool {
    guard configuration(for: provider)?.isValidated == true,
      let keyData = try? credentials.data(for: provider.credentialAccount),
      keyData.isEmpty == false
    else { return false }
    if provider == .azureVision {
      guard let endpoint = configuration(for: provider)?.endpoint else { return false }
      return AzureVisionRecognitionService.isAzureEndpoint(endpoint)
    }
    return true
  }

  func configureGoogle(apiKey: String) throws {
    try configure(provider: .googleVision, endpoint: nil, apiKey: apiKey)
  }

  func configureAzure(endpoint: String, apiKey: String) throws {
    guard let url = URL(string: endpoint), AzureVisionRecognitionService.isAzureEndpoint(url) else {
      throw CloudOCRProviderStoreError.invalidAzureEndpoint
    }
    try configure(provider: .azureVision, endpoint: url, apiKey: apiKey)
  }

  func remove(_ provider: CloudOCRProvider) throws {
    do {
      try credentials.delete(provider.credentialAccount)
    } catch {
      self.error = .security(error)
      throw error
    }
    configurations.removeAll { $0.provider == provider }
    validationStatuses.removeValue(forKey: provider)
    persist()
  }

  func test(_ provider: CloudOCRProvider) async -> CloudCredentialValidation {
    guard let configuration = configuration(for: provider),
      let keyData = try? credentials.data(for: provider.credentialAccount),
      let apiKey = String(data: keyData, encoding: .utf8),
      apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    else {
      let status: CloudCredentialValidation = .notConfigured
      setValidation(status, for: provider)
      return status
    }
    let status = await tester.validate(
      provider: provider,
      endpoint: configuration.endpoint,
      apiKey: apiKey
    )
    setValidation(status, for: provider)
    return status
  }

  func recognizer(for identifier: String) throws -> any TextRecognizing {
    guard let provider = CloudOCRProvider(rawValue: identifier), isSelectable(provider),
      let keyData = try credentials.data(for: provider.credentialAccount),
      let apiKey = String(data: keyData, encoding: .utf8)
    else {
      throw RecognitionError.unavailable("The selected OCR provider is not configured and tested.")
    }
    switch provider {
    case .googleVision: return GoogleVisionRecognitionService(apiKey: apiKey)
    case .azureVision:
      guard let endpoint = configuration(for: provider)?.endpoint else {
        throw RecognitionError.unavailable("Azure AI Vision is not configured.")
      }
      return AzureVisionRecognitionService(endpoint: endpoint, apiKey: apiKey)
    }
  }

  func clearError() { error = nil }

  private func configure(provider: CloudOCRProvider, endpoint: URL?, apiKey: String) throws {
    let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedKey.isEmpty == false else { throw CloudOCRProviderStoreError.invalidAPIKey }
    do {
      try credentials.set(Data(normalizedKey.utf8), for: provider.credentialAccount)
    } catch {
      self.error = .security(error)
      throw error
    }
    upsert(CloudOCRProviderConfiguration(provider: provider, endpoint: endpoint))
    validationStatuses[provider] = .notConfigured
    persist()
  }

  private func setValidation(_ status: CloudCredentialValidation, for provider: CloudOCRProvider) {
    validationStatuses[provider] = status
    guard let configuration = configuration(for: provider) else { return }
    upsert(configuration.settingValidated(status == .valid))
    persist()
  }

  private func upsert(_ configuration: CloudOCRProviderConfiguration) {
    configurations.removeAll { $0.provider == configuration.provider }
    configurations.append(configuration)
    configurations.sort { $0.provider.rawValue < $1.provider.rawValue }
  }

  private func persist() {
    do {
      let archive = CloudOCRProviderArchive(configurations: configurations)
      defaults.set(try JSONEncoder().encode(archive), forKey: Self.archiveDefaultsKey)
      defaults.set(Self.currentSchemaVersion, forKey: Self.schemaVersionDefaultsKey)
      error = nil
    } catch {
      AppLog.recognition.error(
        "cloud_ocr_provider_save_failed type=\(AppLog.errorType(error), privacy: .public)"
      )
      self.error = .persistence(CloudOCRProviderStoreError.serializationFailed)
    }
  }

  private static func load(defaults: UserDefaults) -> (
    configurations: [CloudOCRProviderConfiguration], error: CloudOCRProviderStoreError?
  ) {
    let version = defaults.integer(forKey: schemaVersionDefaultsKey)
    guard version <= currentSchemaVersion else { return ([], .unreadableArchive) }
    guard let data = defaults.data(forKey: archiveDefaultsKey) else {
      defaults.set(currentSchemaVersion, forKey: schemaVersionDefaultsKey)
      return ([], nil)
    }
    do {
      let archive = try JSONDecoder().decode(CloudOCRProviderArchive.self, from: data)
      guard archive.schemaVersion == currentSchemaVersion else { return ([], .unreadableArchive) }
      defaults.set(currentSchemaVersion, forKey: schemaVersionDefaultsKey)
      return (archive.configurations, nil)
    } catch {
      return ([], .unreadableArchive)
    }
  }
}

private struct CloudOCRProviderArchive: Codable {
  let schemaVersion: Int
  let configurations: [CloudOCRProviderConfiguration]

  init(configurations: [CloudOCRProviderConfiguration]) {
    schemaVersion = CloudOCRProviderStore.currentSchemaVersion
    self.configurations = configurations
  }
}
