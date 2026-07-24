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
  @Published private(set) var enhancedModelURL: URL?
  @Published private(set) var error: AppErrorPresentation?

  private let modelsDirectory: URL

  init(modelsDirectory: URL? = nil) {
    let base =
      modelsDirectory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("WriteIt/Models", isDirectory: true)
    self.modelsDirectory = base
    self.error = nil
    self.enhancedModelURL = nil
    do {
      try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    } catch {
      record(ModelStoreError.directoryUnavailable)
    }
    let candidate = base.appendingPathComponent("TrOCRSmallHandwritten.mlmodelc", isDirectory: true)
    enhancedModelURL = FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
  }

  func installEnhancedModel() {
    let panel = NSOpenPanel()
    panel.title = "Install converted handwriting model"
    panel.message = "Choose a compiled Core ML .mlmodelc folder."
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let source = panel.url else { return }
    guard source.pathExtension == "mlmodelc" else {
      error = AppErrorPresentation(
        kind: .configuration,
        title: "Unsupported model",
        message: "Choose a compiled .mlmodelc model."
      )
      return
    }
    let target = modelsDirectory.appendingPathComponent(
      "TrOCRSmallHandwritten.mlmodelc", isDirectory: true)
    do {
      if FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }
      try FileManager.default.copyItem(at: source, to: target)
      enhancedModelURL = target
      error = nil
      AppLog.models.info("local_model_installed")
    } catch {
      record(ModelStoreError.installFailed)
    }
  }

  func removeEnhancedModel() {
    guard let enhancedModelURL else { return }
    do {
      try FileManager.default.removeItem(at: enhancedModelURL)
      self.enhancedModelURL = nil
      error = nil
      AppLog.models.info("local_model_removed")
    } catch {
      record(ModelStoreError.removalFailed)
    }
  }

  func revealEnhancedModel() {
    guard let enhancedModelURL else { return }
    NSWorkspace.shared.activateFileViewerSelecting([enhancedModelURL])
  }

  func clearError() { error = nil }

  private func record(_ error: Error) {
    AppLog.models.error(
      "local_model_storage_failed type=\(AppLog.errorType(error), privacy: .public)")
    self.error = .persistence(error)
  }
}
