import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ReplacementRuleImportExportView: View {
  @ObservedObject var preferences: Preferences
  @State private var message: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Exports only literal and regular-expression replacements. Sample text, history, credentials, and other settings are excluded.")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack {
        Button("Export rules", action: exportRules)
        Button("Import rules", action: importRules)
      }
      if let message {
        Text(message).font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func exportRules() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "WriteItReplacementRules.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try ReplacementRuleArchiveFileStore.write(preferences.exportReplacementRules(), to: url)
      message = "Replacement rules exported."
    } catch {
      message = (error as? LocalizedError)?.errorDescription ?? "Replacement rules could not be exported."
    }
  }

  private func importRules() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try preferences.importReplacementRules(from: ReplacementRuleArchiveFileStore.read(from: url))
      message = "Replacement rules imported."
    } catch {
      message = (error as? LocalizedError)?.errorDescription ?? "Replacement rules could not be imported."
    }
  }
}
