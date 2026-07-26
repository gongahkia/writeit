import SwiftUI

struct ModelCatalogView: View {
  @ObservedObject var preferences: Preferences
  @ObservedObject var models: ModelStore
  @ObservedObject var customModelSource: CustomHTTPSModelSourceStore
  @ObservedObject var cloudProviders: CloudOCRProviderStore
  @ObservedObject var profiles: AppProfileStore
  let profileCreator: CurrentAppProfileCreator
  let registry: RecognitionBackendRegistry
  @State private var selectedTab: ModelCatalogTab = .local

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: WriteItTheme.sectionSpacing) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Recognition").font(.title.bold())
          Text("Choose a local or explicitly configured cloud recognizer.")
            .foregroundStyle(.secondary)
        }
        Picker("Model source", selection: $selectedTab) {
          ForEach(ModelCatalogTab.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        tabContent
      }
      .padding(24)
    }
    .navigationTitle("Models")
  }

  @ViewBuilder private var tabContent: some View {
    switch selectedTab {
    case .local:
      GroupBox("Local recognition") {
        VStack(alignment: .leading, spacing: 10) {
          RecognitionBackendSelectionPicker(
            title: "Global default", selection: $preferences.recognitionBackendID,
            backends: registry.availableBackends
          )
          Text("Apple Vision is built in and processes captures on this Mac.")
            .font(.caption).foregroundStyle(.secondary)
          ForEach(customModelSource.models) { manifest in
            LocalModelRow(manifest: manifest, models: models)
          }
        }
        .padding(6)
      }
    case .cloud:
      ProviderConfigurationPanel(provider: .googleVision, store: cloudProviders)
      ProviderConfigurationPanel(provider: .azureVision, store: cloudProviders)
      AppProfileBackendPanel(
        profiles: profiles, cloudProviders: cloudProviders, profileCreator: profileCreator,
        registry: registry, globalBackendID: preferences.recognitionBackendID
      )
    case .custom:
      CustomModelSourcePanel(source: customModelSource, models: models)
    }
  }
}

private struct LocalModelRow: View {
  let manifest: ModelManifest
  @ObservedObject var models: ModelStore

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text("\(manifest.id) \(manifest.version)")
        Text(stateText).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if case .installed = models.installationState(for: manifest) {
        Button("Remove", role: .destructive) { models.remove(manifest: manifest) }
      }
    }
  }

  private var stateText: String {
    switch models.installationState(for: manifest) {
    case .notInstalled: "Not installed"
    case .downloading(let progress): "Downloading \(Int(progress * 100))%"
    case .paused: "Download paused"
    case .installed: "Installed locally"
    case .failed(let message): message
    }
  }
}

private struct CustomModelSourcePanel: View {
  @ObservedObject var source: CustomHTTPSModelSourceStore
  @ObservedObject var models: ModelStore

  var body: some View {
    GroupBox("Custom HTTPS source") {
      VStack(alignment: .leading, spacing: 10) {
        TextField(
          "HTTPS model manifest URL",
          text: Binding(get: { source.manifestURL }, set: { source.setManifestURL($0) })
        )
        .textContentType(.URL)
        HStack {
          Button("Refresh") { Task { await source.refresh() } }
            .disabled(source.manifestURL.isEmpty || source.isLoading)
          if source.isLoading { ProgressView().controlSize(.small) }
        }
        if let message = source.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        ForEach(source.models) { manifest in
          HStack {
            VStack(alignment: .leading) {
              Text("\(manifest.id) \(manifest.version)")
              Text("\(manifest.assetSizeBytes.formatted(.byteCount(style: .file))) · \(manifest.license)")
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Install") { Task { await source.download(manifest, into: models) } }
              .disabled(!isCompatible(manifest))
          }
        }
      }
      .padding(6)
    }
  }

  private func isCompatible(_ manifest: ModelManifest) -> Bool {
    ModelCompatibilityChecker.failure(
      for: manifest, environment: ModelCompatibilityChecker.currentEnvironment(storageURL: ModelStore.defaultModelsDirectory)
    ) == nil
  }
}
