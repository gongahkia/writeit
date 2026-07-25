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

  init(id: UUID = UUID(), bundleIdentifier: String) throws {
    guard Self.isValid(bundleIdentifier) else { throw AppProfileError.invalidBundleIdentifier }
    self.id = id
    self.bundleIdentifier = bundleIdentifier.lowercased()
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(UUID.self, forKey: .id),
      bundleIdentifier: container.decode(String.self, forKey: .bundleIdentifier)
    )
  }

  private static func isValid(_ value: String) -> Bool {
    guard value.isEmpty == false else { return false }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
    return value.unicodeScalars.allSatisfy(allowed.contains)
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
  nonisolated static let currentSchemaVersion = 1
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
    guard schemaVersion == AppProfileStore.currentSchemaVersion else {
      throw AppProfileStoreError.unsupportedSchema
    }
    self.schemaVersion = schemaVersion
    profiles = try container.decode([AppProfile].self, forKey: .profiles)
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case profiles
  }
}
