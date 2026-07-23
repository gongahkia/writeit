import SwiftUI

struct ModelCatalogView: View {
  @ObservedObject var models: ModelStore
  @ObservedObject var preferences: Preferences
  let recognitionCapabilities: RecognitionBackendCapabilities
  @State private var tab: ModelCatalogTab = .local
  @State private var showSettings = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: WriteItTheme.sectionSpacing) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Model Catalog").font(.title.bold())
            Text("Choose a recognizer and language for handwriting.").foregroundStyle(
              .secondary)
          }
          Spacer()
          Button(action: { showSettings = true }) { Image(systemName: "gearshape") }
            .buttonStyle(.bordered).help("Model settings")
        }
        Picker("Catalog", selection: $tab) {
          ForEach(ModelCatalogTab.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        catalog
      }
      .padding(24)
    }
    .sheet(isPresented: $showSettings) {
      ModelSettingsSheet(
        models: models,
        preferences: preferences,
        recognitionCapabilities: recognitionCapabilities,
        isPresented: $showSettings
      )
    }
  }

  @ViewBuilder private var catalog: some View {
    switch tab {
    case .local:
      VStack(spacing: 14) {
        ModelCard(
          title: "Apple Vision",
          metadata: [
            "Native Apple", languageMetadata, "On-device", "macOS 15+",
          ],
          description: visionDescription,
          status: visionStatus,
          actionTitle: nil,
          action: {}
        )
        ModelCard(
          title: "TrOCR Handwritten",
          metadata: ["English", "Core ML", "Benchmark-gated"],
          description:
            "Experimental. It is not installable until its tokenizer, decoder, and Apple Silicon benchmark qualify.",
          status: .experimental,
          actionTitle: nil,
          action: {}
        )
      }
    case .cloud:
      VStack(spacing: 14) {
        ModelCard(
          title: "Google Cloud Vision",
          metadata: ["Cloud", "Handwriting", "Image only"],
          description:
            "Not configured. Cloud OCR will require an explicit app-profile consent and sends only the rendered ink image.",
          status: .configurationRequired,
          actionTitle: nil,
          action: {}
        )
        ModelCard(
          title: "Azure AI Vision Read",
          metadata: ["Cloud", "Handwriting", "Image only"],
          description:
            "Not configured. Cloud OCR will require an explicit app-profile consent and sends only the rendered ink image.",
          status: .configurationRequired,
          actionTitle: nil,
          action: {}
        )
      }
    case .custom:
      ModelCard(
        title: "Custom OCR Provider",
        metadata: ["HTTP", "Image only", "Per profile"],
        description:
          "Not configured. Custom providers will be validated with a test request before they can be selected.",
        status: .configurationRequired,
        actionTitle: nil,
        action: {}
      )
    }
  }

  private var languageMetadata: String {
    let count = recognitionCapabilities.supportedLanguages.count
    return count == 0 ? "No languages" : "\(count) languages"
  }

  private var visionStatus: LocalModel.Status {
    switch recognitionCapabilities.availability {
    case .available: .builtIn
    case .unavailable: .unavailable
    }
  }

  private var visionDescription: String {
    switch recognitionCapabilities.availability {
    case .available:
      return "Built-in local handwriting recognition. No model download or network access."
    case .unavailable(let message):
      return message
    }
  }
}

private struct ModelCard: View {
  var title: String
  var metadata: [String]
  var description: String
  var status: LocalModel.Status
  var actionTitle: String?
  var action: () -> Void
  var menu: AnyView?

  init(
    title: String, metadata: [String], description: String, status: LocalModel.Status,
    actionTitle: String?, action: @escaping () -> Void, menu: AnyView? = nil
  ) {
    self.title = title
    self.metadata = metadata
    self.description = description
    self.status = status
    self.actionTitle = actionTitle
    self.action = action
    self.menu = menu
  }

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            HStack(spacing: 14) {
              ForEach(metadata, id: \.self) { item in
                Label(item, systemImage: icon(for: item)).font(.subheadline).foregroundStyle(
                  .secondary)
              }
            }
          }
          Spacer()
          HStack(spacing: 8) {
            Label(status.title, systemImage: status.icon)
              .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
              .padding(.horizontal, 10).padding(.vertical, 6)
              .background(.quaternary, in: Capsule())
            if let menu { menu }
          }
        }
        Text(description).foregroundStyle(.secondary)
        if let actionTitle {
          HStack {
            Spacer()
            Button(actionTitle, action: action).buttonStyle(.borderedProminent)
          }
        }
      }
      .padding(6)
    }
  }

  private func icon(for item: String) -> String {
    if item.contains("Apple") { return "apple.logo" }
    if item.contains("Local") || item.contains("device") { return "lock.shield" }
    if item.contains("macOS") { return "laptopcomputer" }
    if item.contains("Core") { return "cpu" }
    return "globe"
  }
}

private struct ModelSettingsSheet: View {
  @ObservedObject var models: ModelStore
  @ObservedObject var preferences: Preferences
  let recognitionCapabilities: RecognitionBackendCapabilities
  @Binding var isPresented: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Text("Model Settings").font(.title2.bold())
        Spacer()
        Button(action: { isPresented = false }) { Image(systemName: "xmark") }.buttonStyle(
          .bordered)
      }
      Picker("Processing", selection: .constant("Recognition")) {
        Text("Recognition").tag("Recognition")
        Text("Enhancement").tag("Enhancement")
      }
      .pickerStyle(.segmented)
      GroupBox("Recognition") {
        VStack(alignment: .leading, spacing: 12) {
          LabeledContent("Primary recognizer", value: "Apple Vision")
          LabeledContent("Language", value: preferences.recognitionLanguage.displayName)
          LabeledContent(
            "Available languages", value: "\(recognitionCapabilities.supportedLanguages.count)")
          LabeledContent("Network access", value: "Never required")
        }
        .padding(6)
      }
      GroupBox("Experimental local models") {
        VStack(alignment: .leading, spacing: 12) {
          Text(
            "No experimental model is currently available. WriteIt will only offer a local model after decoder and benchmark qualification."
          )
        }
        .padding(6)
      }
      Spacer()
    }
    .padding(24)
    .frame(width: 540, height: 400)
  }
}
