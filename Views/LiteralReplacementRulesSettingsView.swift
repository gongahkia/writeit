import SwiftUI

struct LiteralReplacementRulesSettingsView: View {
  @ObservedObject var preferences: Preferences
  @State private var find = ""
  @State private var replacement = ""
  @State private var message: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Applied sequentially to recognized text before optional AI cleanup.")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack {
        TextField("Find", text: $find)
        TextField("Replace with", text: $replacement)
        Button("Add", action: add)
      }
      if preferences.literalReplacementRules.rules.isEmpty {
        Text("No literal replacements.").foregroundStyle(.secondary)
      } else {
        ForEach(preferences.literalReplacementRules.rules) { rule in
          HStack {
            Text(rule.find).lineLimit(1)
            Image(systemName: "arrow.right").accessibilityHidden(true)
            Text(rule.replacement.isEmpty ? "(remove)" : rule.replacement).lineLimit(1)
            Spacer()
            Button("Move up") { preferences.moveLiteralReplacementRule(id: rule.id, by: -1) }
              .disabled(preferences.literalReplacementRules.rules.first?.id == rule.id)
            Button("Move down") { preferences.moveLiteralReplacementRule(id: rule.id, by: 1) }
              .disabled(preferences.literalReplacementRules.rules.last?.id == rule.id)
            Button("Remove", role: .destructive) {
              preferences.removeLiteralReplacementRule(id: rule.id)
            }
          }
        }
      }
      if let message {
        Text(message).font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func add() {
    do {
      try preferences.addLiteralReplacementRule(find: find, replacement: replacement)
      find = ""
      replacement = ""
      message = nil
    } catch {
      message = (error as? LocalizedError)?.errorDescription ?? "Replacement could not be added."
    }
  }
}
