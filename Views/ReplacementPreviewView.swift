import SwiftUI

@MainActor
struct ReplacementPreviewView: View {
  @ObservedObject var preferences: Preferences
  @StateObject private var model: ReplacementPreviewModel

  init(
    preferences: Preferences,
    regexReplacer: any RegexReplacementApplying = RegexReplacementService()
  ) {
    self.preferences = preferences
    _model = StateObject(wrappedValue: ReplacementPreviewModel(regexReplacer: regexReplacer))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Preview")
      Text("Sample text stays in this window. It is not saved or sent.")
        .font(.caption)
        .foregroundStyle(.secondary)
      TextEditor(text: $model.sampleText)
        .font(.body)
        .frame(minHeight: 72)
        .accessibilityLabel("Sample recognition text")
      HStack {
        Text("Result").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Clear sample", action: model.clear).disabled(model.sampleText.isEmpty)
      }
      Text(model.previewText.isEmpty ? "No preview text." : model.previewText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .textSelection(.enabled)
      if let errorMessage = model.errorMessage {
        Text(errorMessage).font(.caption).foregroundStyle(.red)
      }
    }
    .onAppear(perform: updateRules)
    .onChange(of: preferences.literalReplacementRules) { _, _ in updateRules() }
    .onChange(of: preferences.regexReplacementRules) { _, _ in updateRules() }
  }

  private func updateRules() {
    model.updateRules(
      literal: preferences.literalReplacementRules,
      regex: preferences.regexReplacementRules
    )
  }
}
