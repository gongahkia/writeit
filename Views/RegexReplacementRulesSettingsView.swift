import SwiftUI

struct RegexReplacementRulesSettingsView: View {
  @ObservedObject var preferences: Preferences
  @State private var pattern = ""
  @State private var replacement = ""
  @State private var message: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Applied after literal replacements in a local worker. Processing is limited to 500 ms.")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack {
        TextField("Pattern", text: $pattern)
        TextField("Replace with", text: $replacement)
        Button("Add", action: add)
      }
      if preferences.regexReplacementRules.rules.isEmpty {
        Text("No regular-expression replacements.").foregroundStyle(.secondary)
      } else {
        ForEach(preferences.regexReplacementRules.rules) { rule in
          HStack {
            Text(rule.pattern).lineLimit(1)
            Image(systemName: "arrow.right").accessibilityHidden(true)
            Text(rule.replacement.isEmpty ? "(remove)" : rule.replacement).lineLimit(1)
            Spacer()
            Button("Move up") { preferences.moveRegexReplacementRule(id: rule.id, by: -1) }
              .disabled(preferences.regexReplacementRules.rules.first?.id == rule.id)
            Button("Move down") { preferences.moveRegexReplacementRule(id: rule.id, by: 1) }
              .disabled(preferences.regexReplacementRules.rules.last?.id == rule.id)
            Button("Remove", role: .destructive) {
              preferences.removeRegexReplacementRule(id: rule.id)
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
      try preferences.addRegexReplacementRule(pattern: pattern, replacement: replacement)
      pattern = ""
      replacement = ""
      message = nil
    } catch {
      message = (error as? LocalizedError)?.errorDescription ?? "Replacement could not be added."
    }
  }
}
