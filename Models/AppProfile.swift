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
  let overrides: AppProfileOverrides

  init(
    id: UUID = UUID(),
    bundleIdentifier: String,
    overrides: AppProfileOverrides = .init()
  ) throws {
    guard Self.isValid(bundleIdentifier) else { throw AppProfileError.invalidBundleIdentifier }
    self.id = id
    self.bundleIdentifier = bundleIdentifier.lowercased()
    self.overrides = overrides
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(UUID.self, forKey: .id),
      bundleIdentifier: container.decode(String.self, forKey: .bundleIdentifier),
      overrides: container.decodeIfPresent(AppProfileOverrides.self, forKey: .overrides) ?? .init()
    )
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case bundleIdentifier
    case overrides
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

  init(
    recognitionLanguage: RecognitionLanguage? = nil,
    recognitionBackendID: String? = nil
  ) {
    self.recognitionLanguage = recognitionLanguage
    self.recognitionBackendID = recognitionBackendID
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
  nonisolated static let currentSchemaVersion = 2
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
    let data = try JSONEncoder().encode(AppProfileArchive(profiles: profiles))
    defaults.set(data, forKey: Self.archiveDefaultsKey)
    defaults.set(Self.currentSchemaVersion, forKey: Self.schemaVersionDefaultsKey)
    self.profiles = profiles
    error = nil
  }

  func clearError() { error = nil }

  func profile(matching bundleIdentifier: String?) -> AppProfile? {
    guard let bundleIdentifier, let profile = try? AppProfile(bundleIdentifier: bundleIdentifier)
    else { return nil }
    return profiles.first { $0.bundleIdentifier == profile.bundleIdentifier }
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
      if archive.requiresMigration {
        defaults.set(
          try JSONEncoder().encode(AppProfileArchive(profiles: archive.profiles)),
          forKey: archiveDefaultsKey
        )
      }
      defaults.set(currentSchemaVersion, forKey: schemaVersionDefaultsKey)
      return (archive.profiles, nil)
    } catch let error as AppProfileStoreError {
      return ([], error)
    } catch {
      return ([], .unreadableArchive)
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
