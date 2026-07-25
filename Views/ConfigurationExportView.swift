import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationExportView: View {
  @ObservedObject var preferences: Preferences
  @ObservedObject var profiles: AppProfileStore
  @ObservedObject var cloudProviders: CloudOCRProviderStore
  @State private var message: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Exports settings, profiles, consent, replacement rules, custom words, and provider endpoints. Captures, models, diagnostics, API keys, and other Keychain credentials are excluded.")
        .font(.caption)
        .foregroundStyle(.secondary)
      Button("Export configuration", action: exportConfiguration)
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
}
