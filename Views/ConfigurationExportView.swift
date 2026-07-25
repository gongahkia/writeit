import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationExportView: View {
  @ObservedObject var preferences: Preferences
  @ObservedObject var profiles: AppProfileStore
  @ObservedObject var cloudProviders: CloudOCRProviderStore
  @ObservedObject var importer: ConfigurationImportController
  @State private var message: String?
  @State private var confirmsImport = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Exports settings, profiles, consent, replacement rules, custom words, and provider endpoints. Captures, models, diagnostics, API keys, and other Keychain credentials are excluded.")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack {
        Button("Export configuration", action: exportConfiguration)
        Button("Import configuration", action: importConfiguration)
      }
      if let preview = importer.preview {
        Text("Ready to replace settings, \(preview.profiles.count) app profile(s), and \(preview.cloudOCRProviders.count) provider endpoint(s). Credentials remain local and require a fresh validation.")
          .font(.caption)
          .foregroundStyle(.secondary)
        HStack {
          Button("Apply imported configuration", action: { confirmsImport = true })
            .confirmationDialog(
              "Replace current configuration?", isPresented: $confirmsImport,
              titleVisibility: .visible
            ) {
              Button("Replace configuration", role: .destructive, action: importer.applyPreview)
            } message: {
              Text("This replaces exported settings, profiles, and provider endpoints. Credentials, history, models, and diagnostics are unchanged.")
            }
          Button("Discard import", action: importer.clearPreview)
        }
      }
      if let status = importer.status {
        Text(status).font(.caption).foregroundStyle(.secondary)
      }
      if let error = importer.error {
        CaptureErrorBanner(error: error, dismiss: importer.clearError)
      }
      if let message {
        Text(message).font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func exportConfiguration() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "WriteItConfiguration.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let archive = ConfigurationArchive(
        preferences: preferences,
        profiles: profiles.profiles,
        cloudOCRProviders: cloudProviders.configurations
      )
      try ConfigurationArchiveFileStore.write(ConfigurationArchiveCodec.encode(archive), to: url)
      message = "Configuration exported."
    } catch {
      message = (error as? LocalizedError)?.errorDescription ?? "Configuration could not be exported."
    }
  }

  private func importConfiguration() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    importer.previewFile(at: url)
  }
}
