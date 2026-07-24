import AppKit
import Combine
import Foundation

enum ModelStoreError: LocalizedError, Equatable {
  case directoryUnavailable
  case installFailed
  case removalFailed

  var errorDescription: String? {
    switch self {
    case .directoryUnavailable: "WriteIt could not prepare local model storage."
    case .installFailed: "WriteIt could not install the selected model."
    case .removalFailed: "WriteIt could not delete the selected model."
    }
  }
}

@MainActor
final class ModelStore: ObservableObject {
  @Published private(set) var installationStates: [String: ModelInstallationState]
  @Published private(set) var error: AppErrorPresentation?

  private let modelsDirectory: URL

  init(modelsDirectory: URL? = nil) {
    let base =
      modelsDirectory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("WriteIt/Models", isDirectory: true)
    self.modelsDirectory = base
    self.error = nil
    self.installationStates = [:]
    do {
      try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    } catch {
      record(ModelStoreError.directoryUnavailable)
    }
  }

  func installationState(for manifest: ModelManifest) -> ModelInstallationState {
    if let installed = ManifestModelInstaller.installedAssetURL(for: manifest, in: modelsDirectory) {
      return .installed(installed)
    }
    return installationStates[installationKey(for: manifest)] ?? .notInstalled
  }

  func install(manifest: ModelManifest, stagedAssetURL: URL) {
    do {
      let installed = try ManifestModelInstaller.install(
        manifest: manifest,
        stagedAssetURL: stagedAssetURL,
        in: modelsDirectory
      )
      installationStates[installationKey(for: manifest)] = .installed(installed)
      error = nil
      AppLog.models.info("local_model_installed")
    } catch {
      record(ModelStoreError.installFailed)
    }
  }

  func remove(manifest: ModelManifest) {
    do {
      try ManifestModelInstaller.remove(manifest: manifest, in: modelsDirectory)
      installationStates[installationKey(for: manifest)] = .notInstalled
      error = nil
      AppLog.models.info("local_model_removed")
    } catch {
      record(ModelStoreError.removalFailed)
    }
  }

  func reveal(manifest: ModelManifest) {
    guard let installed = ManifestModelInstaller.installedAssetURL(for: manifest, in: modelsDirectory) else {
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([installed])
  }

  func clearError() { error = nil }

  private func record(_ error: Error) {
    AppLog.models.error(
      "local_model_storage_failed type=\(AppLog.errorType(error), privacy: .public)")
    self.error = .persistence(error)
  }

  private func installationKey(for manifest: ModelManifest) -> String {
    "\(manifest.id)@\(manifest.version)"
  }
}
