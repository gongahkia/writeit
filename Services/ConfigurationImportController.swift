import Combine
import Foundation

@MainActor
protocol ConfigurationStateManaging: AnyObject {
  func snapshot() -> ConfigurationRuntimeSnapshot
  func apply(_ archive: ConfigurationArchive) throws
  func restore(_ snapshot: ConfigurationRuntimeSnapshot) throws
}

struct ConfigurationRuntimeSnapshot: Equatable {
  let archive: ConfigurationArchive
  let cloudOCRProviders: [CloudOCRProviderConfiguration]
  let cloudOCRValidationStatuses: [CloudOCRProvider: CloudCredentialValidation]
}

@MainActor
final class ConfigurationStateStore: ConfigurationStateManaging {
  private let preferences: Preferences
  private let profiles: AppProfileStore
  private let cloudProviders: CloudOCRProviderStore

  init(
    preferences: Preferences,
    profiles: AppProfileStore,
    cloudProviders: CloudOCRProviderStore
  ) {
    self.preferences = preferences
    self.profiles = profiles
    self.cloudProviders = cloudProviders
  }

  func snapshot() -> ConfigurationRuntimeSnapshot {
    ConfigurationRuntimeSnapshot(
      archive: ConfigurationArchive(
        preferences: preferences,
        profiles: profiles.profiles,
        cloudOCRProviders: cloudProviders.configurations
      ),
      cloudOCRProviders: cloudProviders.configurations,
      cloudOCRValidationStatuses: cloudProviders.validationStatuses
    )
  }

  func apply(_ archive: ConfigurationArchive) throws {
    try archive.validated()
    try preferences.replaceConfiguration(archive.preferences)
    try profiles.replaceProfiles(archive.profiles)
    try cloudProviders.replaceConfigurations(archive.cloudOCRProviders)
  }

  func restore(_ snapshot: ConfigurationRuntimeSnapshot) throws {
    try preferences.replaceConfiguration(snapshot.archive.preferences)
    try profiles.replaceProfiles(snapshot.archive.profiles)
    try cloudProviders.restoreConfigurations(
      snapshot.cloudOCRProviders,
      validationStatuses: snapshot.cloudOCRValidationStatuses
    )
  }
}

@MainActor
final class ConfigurationImportController: ObservableObject {
  @Published private(set) var preview: ConfigurationArchive?
  @Published private(set) var error: AppErrorPresentation?
  @Published private(set) var status: String?

  private let state: any ConfigurationStateManaging

  init(state: any ConfigurationStateManaging) {
    self.state = state
  }

  func preview(_ data: Data) {
    do {
      preview = try ConfigurationArchiveCodec.decode(data)
      error = nil
      status = nil
    } catch {
      preview = nil
      status = nil
      self.error = .persistence(error)
    }
  }

  func previewFile(at url: URL) {
    do {
      preview(try ConfigurationArchiveFileStore.read(from: url))
    } catch {
      preview = nil
      status = nil
      self.error = .persistence(error)
    }
  }

  func applyPreview() {
    guard let preview else { return }
    let previous = state.snapshot()
    do {
      try state.apply(preview)
      self.preview = nil
      error = nil
      status = "Configuration imported."
    } catch {
      do {
        try state.restore(previous)
      } catch {
        self.preview = nil
        self.error = .persistence(ConfigurationArchiveError.rollbackFailed)
        status = nil
        return
      }
      self.error = .persistence(error)
      status = nil
    }
  }

  func clearPreview() { preview = nil }
  func clearError() { error = nil }
  func clearStatus() { status = nil }
}
