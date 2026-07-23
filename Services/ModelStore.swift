import AppKit
import Combine
import Foundation

@MainActor
final class ModelStore: ObservableObject {
  @Published private(set) var enhancedModelURL: URL?
  @Published private(set) var lastError: String?

  private let modelsDirectory: URL

  init(modelsDirectory: URL? = nil) {
    let base =
      modelsDirectory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("WriteIt/Models", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    self.modelsDirectory = base
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
      lastError = "Choose a compiled .mlmodelc model."
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
      lastError = nil
      AppLog.models.info("local_model_installed")
    } catch {
      lastError = "Could not install the selected model."
      AppLog.models.error(
        "local_model_install_failed type=\(AppLog.errorType(error), privacy: .public)")
    }
  }

  func removeEnhancedModel() {
    guard let enhancedModelURL else { return }
    do {
      try FileManager.default.removeItem(at: enhancedModelURL)
      self.enhancedModelURL = nil
      AppLog.models.info("local_model_removed")
    } catch {
      lastError = "Could not delete the selected model."
      AppLog.models.error(
        "local_model_delete_failed type=\(AppLog.errorType(error), privacy: .public)")
    }
  }

  func revealEnhancedModel() {
    guard let enhancedModelURL else { return }
    NSWorkspace.shared.activateFileViewerSelecting([enhancedModelURL])
  }
}
