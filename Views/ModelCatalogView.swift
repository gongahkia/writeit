import SwiftUI

struct ModelCatalogView: View {
  @ObservedObject var model: AppModel
  @State private var tab: ModelCatalogTab = .local
  @State private var showSettings = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Model Catalog").font(.title.bold())
            Text("Choose the on-device recognizer used for handwriting.").foregroundStyle(.secondary)
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
      ModelSettingsSheet(model: model, isPresented: $showSettings)
    }
  }

  @ViewBuilder private var catalog: some View {
    switch tab {
    case .local:
      VStack(spacing: 14) {
        ModelCard(
          title: "Apple Vision",
          metadata: ["Native Apple", "English", "On-device", "macOS 15+"],
          description: "Built-in local handwriting recognition. No model download or network access.",
          status: .builtIn,
          actionTitle: nil,
          action: {}
        )
        ModelCard(
          title: "TrOCR Small Handwritten",
          metadata: ["English", "Core ML", "Local file"],
          description: model.models.enhancedModelURL == nil ? "Install a compiled .mlmodelc package to manage an enhanced local handwriting model." : "A compiled Core ML package is stored locally and ready for enhanced-model integration.",
          status: model.models.enhancedModelURL == nil ? .available : .installed,
          actionTitle: model.models.enhancedModelURL == nil ? "Install…" : nil,
          action: model.models.installEnhancedModel,
          menu: model.models.enhancedModelURL == nil ? nil : AnyView(ModelMenu(model: model))
        )
        if let error = model.models.lastError { Text(error).font(.caption).foregroundStyle(.red) }
      }
    case .cloud:
      ContentUnavailableView("No cloud recognition", systemImage: "cloud.slash", description: Text("WriteIt keeps handwriting recognition on-device. AI cleanup is configured separately."))
        .frame(maxWidth: .infinity, minHeight: 260)
    case .custom:
      ContentUnavailableView("Custom providers", systemImage: "slider.horizontal.3", description: Text("Custom OCR providers are not enabled in this local-first release."))
        .frame(maxWidth: .infinity, minHeight: 260)
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

  init(title: String, metadata: [String], description: String, status: LocalModel.Status, actionTitle: String?, action: @escaping () -> Void, menu: AnyView? = nil) {
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
                Label(item, systemImage: icon(for: item)).font(.subheadline).foregroundStyle(.secondary)
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
          HStack { Spacer(); Button(actionTitle, action: action).buttonStyle(.borderedProminent) }
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

private struct ModelMenu: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Menu {
      Button("Show in Finder", action: model.models.revealEnhancedModel)
      Divider()
      Button("Delete Model", role: .destructive, action: model.models.removeEnhancedModel)
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .menuStyle(.borderlessButton)
  }
}

private struct ModelSettingsSheet: View {
  @ObservedObject var model: AppModel
  @Binding var isPresented: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Text("Model Settings").font(.title2.bold())
        Spacer()
        Button(action: { isPresented = false }) { Image(systemName: "xmark") }.buttonStyle(.bordered)
      }
      Picker("Processing", selection: .constant("Recognition")) {
        Text("Recognition").tag("Recognition")
        Text("Enhancement").tag("Enhancement")
      }
      .pickerStyle(.segmented)
      GroupBox("Recognition") {
        VStack(alignment: .leading, spacing: 12) {
          LabeledContent("Primary recognizer", value: "Apple Vision")
          LabeledContent("Language", value: "English")
          LabeledContent("Network access", value: "Never required")
        }
        .padding(6)
      }
      GroupBox("Enhanced local model") {
        VStack(alignment: .leading, spacing: 12) {
          Text(model.models.enhancedModelURL == nil ? "No compiled Core ML model installed." : "Compiled Core ML model installed locally.")
          HStack {
            if model.models.enhancedModelURL == nil { Button("Install model…", action: model.models.installEnhancedModel) }
            else {
              Button("Show in Finder", action: model.models.revealEnhancedModel)
              Button("Delete", role: .destructive, action: model.models.removeEnhancedModel)
            }
          }
        }
        .padding(6)
      }
      Spacer()
    }
    .padding(24)
    .frame(width: 540, height: 400)
  }
}
