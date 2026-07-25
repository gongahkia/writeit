import SwiftUI

struct DiagnosticsPrivacyPanel: View {
  @ObservedObject var preferences: Preferences
  @ObservedObject var diagnostics: DiagnosticEventStore
  @ObservedObject var metrics: AnonymousMetricsQueue

  var body: some View {
    let presentation = PrivacyControlsPresentation(
      retainsDiagnosticLogs: preferences.retainsLocalLogs,
      sharesAnonymousMetrics: preferences.allowsAnonymousMetrics
    )
    VStack(alignment: .leading, spacing: WriteItTheme.compactSpacing) {
      VStack(alignment: .leading, spacing: 3) {
        Label("Diagnostics and metrics", systemImage: "lock.shield")
          .font(.headline)
        Text("These controls are local and optional. They never include capture content.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Divider()
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Label("Diagnostics", systemImage: "stethoscope")
            .font(.subheadline)
          Spacer()
          Label(presentation.diagnosticsTitle, systemImage: presentation.diagnosticsSymbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(preferences.retainsLocalLogs ? Color.secondary : .orange)
        }
        Toggle("Retain diagnostic logs", isOn: $preferences.retainsLocalLogs)
          .onChange(of: preferences.retainsLocalLogs) { _, retainsLocalLogs in
            setDiagnosticRetention(retainsLocalLogs)
          }
        Text("Turning this off immediately deletes local diagnostic events and prevents new events from being saved.")
          .font(.caption)
          .foregroundStyle(.secondary)
        DiagnosticExportView(diagnostics: diagnostics)
      }
      Divider()
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Label("Anonymous metrics", systemImage: "chart.line.uptrend.xyaxis")
            .font(.subheadline)
          Spacer()
          Label(presentation.metricsTitle, systemImage: presentation.metricsSymbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(preferences.allowsAnonymousMetrics ? Color.green : .secondary)
        }
        Toggle("Share anonymous metrics", isOn: $preferences.allowsAnonymousMetrics)
          .onChange(of: preferences.allowsAnonymousMetrics) { _, allowsAnonymousMetrics in
            setMetricsConsent(allowsAnonymousMetrics)
          }
        Text("Optional fixed lifecycle codes are queued locally only. This build does not send metrics.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(WriteItTheme.compactSpacing)
    .background(
      WriteItTheme.cardFill,
      in: RoundedRectangle(cornerRadius: WriteItTheme.cardCornerRadius)
    )
    .overlay(
      RoundedRectangle(cornerRadius: WriteItTheme.cardCornerRadius).stroke(WriteItTheme.cardStroke)
    )
  }

  private func setDiagnosticRetention(_ retainsLocalLogs: Bool) {
    diagnostics.setRetainsLocalLogs(retainsLocalLogs)
  }

  private func setMetricsConsent(_ allowsAnonymousMetrics: Bool) {
    metrics.setConsent(allowsAnonymousMetrics)
  }
}
