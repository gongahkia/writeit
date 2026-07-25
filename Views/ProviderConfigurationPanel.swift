import SwiftUI

struct ProviderConfigurationPanel: View {
  let provider: CloudOCRProvider
  @ObservedObject var store: CloudOCRProviderStore
  @State private var endpoint: String
  @State private var apiKey = ""
  @State private var feedback: String?

  init(provider: CloudOCRProvider, store: CloudOCRProviderStore) {
    self.provider = provider
    self.store = store
    _endpoint = State(initialValue: store.configuration(for: provider)?.endpoint?.absoluteString ?? "")
  }

  var body: some View {
    GroupBox(provider.displayName) {
      VStack(alignment: .leading, spacing: 12) {
        Text("Cloud OCR sends the rendered ink image to this provider only after current app-profile consent.")
          .font(.caption)
          .foregroundStyle(.secondary)
        if provider == .azureVision {
          TextField("Azure endpoint", text: $endpoint)
            .textContentType(.URL)
        }
        SecureField("API key", text: $apiKey)
        HStack {
          Button("Save configuration", action: save)
          Button("Test connection", action: test)
            .disabled(store.configuration(for: provider) == nil)
          Button("Remove", role: .destructive, action: remove)
            .disabled(store.configuration(for: provider) == nil)
        }
        status
      }
      .padding(6)
    }
  }

  @ViewBuilder private var status: some View {
    if let feedback {
      Text(feedback).font(.caption).foregroundStyle(.secondary)
    } else if store.isSelectable(provider) {
      Label("Tested and selectable", systemImage: "checkmark.circle")
        .font(.caption).foregroundStyle(.secondary)
    } else if store.configuration(for: provider) != nil {
      Label("Configuration saved; test connection before selecting", systemImage: "exclamationmark.triangle")
        .font(.caption).foregroundStyle(.secondary)
    } else {
      Label("Not configured", systemImage: "key")
        .font(.caption).foregroundStyle(.secondary)
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
