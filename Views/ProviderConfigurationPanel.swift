import SwiftUI

struct ProviderConfigurationPanel: View {
  let provider: CloudOCRProvider
  @ObservedObject var store: CloudOCRProviderStore
  @State private var endpoint: String
  @State private var apiKey = ""
  @State private var feedback: String?
  @State private var showsRemovalConfirmation = false

  init(provider: CloudOCRProvider, store: CloudOCRProviderStore) {
    self.provider = provider
    self.store = store
    _endpoint = State(initialValue: store.configuration(for: provider)?.endpoint?.absoluteString ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: WriteItTheme.compactSpacing) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 3) {
          Label(provider.displayName, systemImage: "cloud")
            .font(.headline)
          Text("Cloud OCR sends rendered ink only after current app-profile consent.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Label(configurationStatus.title, systemImage: configurationStatus.symbol)
          .font(.caption.weight(.semibold))
          .foregroundStyle(configurationStatus == .selectable ? .green : .secondary)
      }
      Divider()
      if provider == .azureVision {
        TextField("Azure endpoint", text: $endpoint)
          .textContentType(.URL)
      }
      SecureField(apiKeyLabel, text: $apiKey)
      Text("The API key is stored in Keychain. Testing does not send capture ink.")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack {
        Button("Save configuration", systemImage: "key.fill", action: save)
          .buttonStyle(.borderedProminent)
        Button("Test connection", systemImage: "checkmark.shield", action: test)
          .buttonStyle(.bordered)
          .disabled(store.configuration(for: provider) == nil)
        Spacer()
        Button(
          "Remove", systemImage: "trash", role: .destructive,
          action: { showsRemovalConfirmation = true }
        )
        .buttonStyle(.bordered)
        .disabled(store.configuration(for: provider) == nil)
      }
      status
    }
    .padding(WriteItTheme.compactSpacing)
    .background(
      WriteItTheme.cardFill,
      in: RoundedRectangle(cornerRadius: WriteItTheme.cardCornerRadius)
    )
    .overlay(
      RoundedRectangle(cornerRadius: WriteItTheme.cardCornerRadius).stroke(WriteItTheme.cardStroke)
    )
    .confirmationDialog(
      "Remove (provider.displayName) configuration?",
      isPresented: $showsRemovalConfirmation,
      titleVisibility: .visible
    ) {
      Button("Remove configuration", role: .destructive, action: remove)
    } message: {
      Text("This removes the API key from Keychain and disables this provider.")
    }
  }

  @ViewBuilder private var status: some View {
    if let feedback {
      Text(feedback).font(.caption).foregroundStyle(.secondary)
    } else {
      Text(statusDetail).font(.caption).foregroundStyle(.secondary)
    }
  }

  private var configurationStatus: ProviderConfigurationStatus {
    ProviderConfigurationStatus(
      isConfigured: store.configuration(for: provider) != nil,
      isSelectable: store.isSelectable(provider)
    )
  }

  private var apiKeyLabel: String {
    store.configuration(for: provider) == nil ? "API key" : "Replace API key"
  }

  private var statusDetail: String {
    switch configurationStatus {
    case .notConfigured: "Add an API key to configure this provider."
    case .requiresValidation: "Configuration saved. Test the connection before selecting it."
    case .selectable: "Tested and selectable for apps that grant cloud OCR consent."
    }
  }

  private func save() {
    do {
      switch provider {
      case .googleVision: try store.configureGoogle(apiKey: apiKey)
      case .azureVision: try store.configureAzure(endpoint: endpoint, apiKey: apiKey)
      }
      apiKey = ""
      feedback = "Configuration saved. Test the connection before selecting it."
    } catch {
      feedback = (error as? LocalizedError)?.errorDescription ?? "Configuration could not be saved."
    }
  }

  private func test() {
    Task { @MainActor in
      feedback = statusMessage(for: await store.test(provider))
    }
  }

  private func remove() {
    do {
      try store.remove(provider)
      apiKey = ""
      endpoint = ""
      feedback = "Configuration removed."
    } catch {
      feedback = (error as? LocalizedError)?.errorDescription ?? "Configuration could not be removed."
    }
  }

  private func statusMessage(for status: CloudCredentialValidation) -> String {
    switch status {
    case .valid: "Connection tested successfully."
    case .invalidCredentials: "Credentials were rejected."
    case .notConfigured: "Save a valid configuration before testing."
    case .unavailable: "The provider is unavailable."
    case .cancelled: "Connection test cancelled."
    }
  }
}
