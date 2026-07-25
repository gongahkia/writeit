import Combine
import Foundation

enum AppProfileError: LocalizedError, Equatable {
  case invalidBundleIdentifier

  var errorDescription: String? {
    switch self {
    case .invalidBundleIdentifier: "The app profile bundle identifier is invalid."
    }
  }
}

struct AppProfile: Codable, Sendable, Equatable, Identifiable {
  let id: UUID
  let bundleIdentifier: String
  let isEnabled: Bool
  let overrides: AppProfileOverrides

  init(
    id: UUID = UUID(),
    bundleIdentifier: String,
    isEnabled: Bool = true,
    overrides: AppProfileOverrides = .init()
  ) throws {
    guard Self.isValid(bundleIdentifier) else { throw AppProfileError.invalidBundleIdentifier }
    self.init(
      id: id,
      canonicalBundleIdentifier: bundleIdentifier.lowercased(),
      isEnabled: isEnabled,
      overrides: overrides
    )
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(UUID.self, forKey: .id),
      bundleIdentifier: container.decode(String.self, forKey: .bundleIdentifier),
      isEnabled: container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
      overrides: container.decodeIfPresent(AppProfileOverrides.self, forKey: .overrides) ?? .init()
    )
  }

  func settingEnabled(_ isEnabled: Bool) -> Self {
    Self(
      id: id,
      canonicalBundleIdentifier: bundleIdentifier,
      isEnabled: isEnabled,
      overrides: overrides
    )
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case bundleIdentifier
    case isEnabled
    case overrides
  }

  private init(
    id: UUID,
    canonicalBundleIdentifier: String,
    isEnabled: Bool,
    overrides: AppProfileOverrides
  ) {
    self.id = id
    self.bundleIdentifier = canonicalBundleIdentifier
    self.isEnabled = isEnabled
    self.overrides = overrides
  }

  private static func isValid(_ value: String) -> Bool {
    guard value.isEmpty == false else { return false }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
    return value.unicodeScalars.allSatisfy(allowed.contains)
  }
}

struct AppProfileOverrides: Codable, Sendable, Equatable {
  let recognitionLanguage: RecognitionLanguage?
  let recognitionBackendID: String?
  let outputStrategy: OutputStrategy?
  let aiCleanupEnabled: Bool?
  let customWords: CustomWordList?

  init(
    recognitionLanguage: RecognitionLanguage? = nil,
    recognitionBackendID: String? = nil,
    outputStrategy: OutputStrategy? = nil,
    aiCleanupEnabled: Bool? = nil,
    customWords: CustomWordList? = nil
  ) {
    self.recognitionLanguage = recognitionLanguage
    self.recognitionBackendID = recognitionBackendID
    self.outputStrategy = outputStrategy
    self.aiCleanupEnabled = aiCleanupEnabled
    self.customWords = customWords
  }
}

enum AppProfileOverrideResolution {
  static func value<Value>(profileOverride: Value?, global: Value) -> Value {
    profileOverride ?? global
  }
}

@MainActor
final class AppProfileOverrideResolver {
  private let profiles: AppProfileStore

  init(profiles: AppProfileStore) {
    self.profiles = profiles
  }

  func value<Value>(
    for bundleIdentifier: String?,
    override: KeyPath<AppProfileOverrides, Value?>,
    global: Value
  ) -> Value {
    let profileOverride = profiles.profile(matching: bundleIdentifier).flatMap {
      $0.overrides[keyPath: override]
    }
    return AppProfileOverrideResolution.value(
      profileOverride: profileOverride,
      global: global
    )
  }
}

enum AppProfileStoreError: LocalizedError, Equatable {
  case unreadableArchive
  case unsupportedSchema

  var errorDescription: String? {
    switch self {
    case .unreadableArchive: "Saved app profiles could not be read."
    case .unsupportedSchema: "Saved app profiles use an unsupported schema."
    }
  }
}

@MainActor
final class AppProfileStore: ObservableObject {
  nonisolated static let currentSchemaVersion = 3
  nonisolated static let archiveDefaultsKey = "appProfiles.archive"
  nonisolated static let schemaVersionDefaultsKey = "appProfiles.schemaVersion"

  @Published private(set) var profiles: [AppProfile]
  @Published private(set) var error: AppProfileStoreError?

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let result = Self.load(from: defaults)
    profiles = result.profiles
    error = result.error
  }

  func replaceProfiles(_ profiles: [AppProfile]) throws {
    let normalizedProfiles = Self.normalizedProfiles(profiles)
    let data = try JSONEncoder().encode(AppProfileArchive(profiles: normalizedProfiles))
    defaults.set(data, forKey: Self.archiveDefaultsKey)
    defaults.set(Self.currentSchemaVersion, forKey: Self.schemaVersionDefaultsKey)
    self.profiles = normalizedProfiles
    error = nil
  }

  func clearError() { error = nil }

  func setEnabled(_ isEnabled: Bool, for profileID: UUID) throws {
    try replaceProfiles(profiles.map {
      $0.id == profileID ? $0.settingEnabled(isEnabled) : $0
    })
  }

  func profile(matching bundleIdentifier: String?, includingDisabled: Bool = false) -> AppProfile? {
    guard let bundleIdentifier, let profile = try? AppProfile(bundleIdentifier: bundleIdentifier)
    else { return nil }
    return profiles.first {
      $0.bundleIdentifier == profile.bundleIdentifier && (includingDisabled || $0.isEnabled)
    }
  }

  private static func load(from defaults: UserDefaults) -> (profiles: [AppProfile], error: AppProfileStoreError?) {
    let storedSchemaVersion = defaults.integer(forKey: schemaVersionDefaultsKey)
    guard storedSchemaVersion <= currentSchemaVersion else {
      return ([], .unsupportedSchema)
    }
    guard let data = defaults.data(forKey: archiveDefaultsKey) else {
      defaults.set(currentSchemaVersion, forKey: schemaVersionDefaultsKey)
      return ([], nil)
    }
    do {
      let archive = try JSONDecoder().decode(AppProfileArchive.self, from: data)
      let normalizedProfiles = normalizedProfiles(archive.profiles)
      if archive.requiresMigration || normalizedProfiles != archive.profiles {
        defaults.set(
          try JSONEncoder().encode(AppProfileArchive(profiles: normalizedProfiles)),
          forKey: archiveDefaultsKey
        )
      }
      defaults.set(currentSchemaVersion, forKey: schemaVersionDefaultsKey)
      return (normalizedProfiles, nil)
    } catch let error as AppProfileStoreError {
      return ([], error)
    } catch {
      return ([], .unreadableArchive)
    }
  }

  private static func normalizedProfiles(_ profiles: [AppProfile]) -> [AppProfile] {
    var activeBundleIdentifiers: Set<String> = []
    return profiles.map { profile in
      guard profile.isEnabled else { return profile }
      guard activeBundleIdentifiers.insert(profile.bundleIdentifier).inserted else {
        return profile.settingEnabled(false)
      }
      return profile
    }
  }
}

private struct AppProfileArchive: Codable {
  let schemaVersion: Int
  let profiles: [AppProfile]

  init(profiles: [AppProfile]) {
    schemaVersion = AppProfileStore.currentSchemaVersion
    self.profiles = profiles
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    guard (1...AppProfileStore.currentSchemaVersion).contains(schemaVersion) else {
      throw AppProfileStoreError.unsupportedSchema
    }
    self.schemaVersion = schemaVersion
    profiles = try container.decode([AppProfile].self, forKey: .profiles)
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case profiles
  }

  var requiresMigration: Bool { schemaVersion < AppProfileStore.currentSchemaVersion }
}
