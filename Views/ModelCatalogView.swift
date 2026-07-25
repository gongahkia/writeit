import SwiftUI

struct ModelCatalogView: View {
  @ObservedObject var preferences: Preferences
  @ObservedObject var cloudProviders: CloudOCRProviderStore
  @ObservedObject var profiles: AppProfileStore
  let profileCreator: CurrentAppProfileCreator
  let registry: RecognitionBackendRegistry

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: WriteItTheme.sectionSpacing) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Recognition").font(.title.bold())
          Text("Choose a local or explicitly configured cloud recognizer.")
            .foregroundStyle(.secondary)
        }
        GroupBox("Default recognizer") {
          RecognitionBackendSelectionPicker(
            title: "Global default",
            selection: $preferences.recognitionBackendID,
            backends: registry.availableBackends
          )
          .padding(6)
        }
        ProviderConfigurationPanel(provider: .googleVision, store: cloudProviders)
        ProviderConfigurationPanel(provider: .azureVision, store: cloudProviders)
        AppProfileBackendPanel(
          profiles: profiles,
          cloudProviders: cloudProviders,
          profileCreator: profileCreator,
          registry: registry,
          globalBackendID: preferences.recognitionBackendID
        )
      }
      .padding(24)
    }
    .navigationTitle("Models")
  }
}
