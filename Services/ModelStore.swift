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
  private let downloadCheckpointStore: ModelDownloadCheckpointStore
  private var downloadCheckpoints: [String: ModelDownloadCheckpoint]

  init(modelsDirectory: URL? = nil, downloadCheckpointURL: URL? = nil) {
    let base =
      modelsDirectory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("WriteIt/Models", isDirectory: true)
    self.modelsDirectory = base
    self.downloadCheckpointStore = ModelDownloadCheckpointStore(
      fileURL: downloadCheckpointURL ?? base.appendingPathComponent("downloads.json"))
    self.error = nil
    self.installationStates = [:]
    self.downloadCheckpoints = [:]
    do {
      try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    } catch {
      record(ModelStoreError.directoryUnavailable)
    }
    do {
      let checkpoints = try downloadCheckpointStore.load()
      downloadCheckpoints = Dictionary(
        uniqueKeysWithValues: checkpoints.map { (installationKey(for: $0.manifest), $0) })
      for checkpoint in checkpoints {
        installationStates[installationKey(for: checkpoint.manifest)] = .paused(
          progress: checkpoint.progress)
      }
    } catch {
      record(error)
    }
  }

  func installationState(for manifest: ModelManifest) -> ModelInstallationState {
    if let installed = ManifestModelInstaller.installedAssetURL(for: manifest, in: modelsDirectory) {
      return .installed(installed)
    }
    return installationStates[installationKey(for: manifest)] ?? .notInstalled
  }

  func install(manifest: ModelManifest, stagedAssetURL: URL) {
    if let failure = ModelCompatibilityChecker.failure(
      for: manifest,
      environment: ModelCompatibilityChecker.currentEnvironment(storageURL: modelsDirectory)
    ) {
      installationStates[installationKey(for: manifest)] = .failed(
        failure.errorDescription ?? "Model compatibility check failed.")
      error = AppErrorPresentation(kind: .configuration, title: "Model unavailable", message: failure.errorDescription ?? "Model compatibility check failed.")
      return
    }
    do {
      let installed = try ManifestModelInstaller.install(
        manifest: manifest,
        stagedAssetURL: stagedAssetURL,
        in: modelsDirectory
      )
      installationStates[installationKey(for: manifest)] = .installed(installed)
      clearDownloadCheckpoint(for: manifest)
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

  func downloadCheckpoint(for manifest: ModelManifest) -> ModelDownloadCheckpoint? {
    downloadCheckpoints[installationKey(for: manifest)]
  }

  func resumeDownload(for manifest: ModelManifest) -> Data? {
    let checkpoint = downloadCheckpoint(for: manifest)
    installationStates[installationKey(for: manifest)] = .downloading(
      progress: checkpoint?.progress ?? 0)
    return checkpoint?.resumeData
  }

  func recordDownloadProgress(
    for manifest: ModelManifest,
    progress: Double,
    resumeData: Data?
  ) {
    let checkpoint = ModelDownloadCheckpoint(
      schemaVersion: ModelDownloadCheckpoint.currentSchemaVersion,
      manifest: manifest,
      progress: min(max(progress, 0), 1),
      resumeData: resumeData
    )
    downloadCheckpoints[installationKey(for: manifest)] = checkpoint
    persistDownloadCheckpoints()
    installationStates[installationKey(for: manifest)] = .downloading(progress: checkpoint.progress)
  }

  func pauseDownload(for manifest: ModelManifest, resumeData: Data?) {
    recordDownloadProgress(
      for: manifest,
      progress: downloadCheckpoint(for: manifest)?.progress ?? 0,
      resumeData: resumeData
    )
    installationStates[installationKey(for: manifest)] = .paused(
      progress: downloadCheckpoint(for: manifest)?.progress ?? 0)
  }

  private func record(_ error: Error) {
    AppLog.models.error(
      "local_model_storage_failed type=\(AppLog.errorType(error), privacy: .public)")
    self.error = .persistence(error)
  }

  private func installationKey(for manifest: ModelManifest) -> String {
    "\(manifest.id)@\(manifest.version)"
  }

  private func persistDownloadCheckpoints() {
    do {
      try downloadCheckpointStore.save(Array(downloadCheckpoints.values))
    } catch {
      record(error)
    }
  }

  private func clearDownloadCheckpoint(for manifest: ModelManifest) {
    downloadCheckpoints.removeValue(forKey: installationKey(for: manifest))
    persistDownloadCheckpoints()
  }
}
