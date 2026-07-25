struct PrivacyControlsPresentation: Equatable {
  let retainsDiagnosticLogs: Bool
  let sharesAnonymousMetrics: Bool

  var diagnosticsTitle: String {
    retainsDiagnosticLogs ? "Local diagnostics retained" : "Diagnostics not retained"
  }

  var diagnosticsSymbol: String {
    retainsDiagnosticLogs ? "internaldrive" : "internaldrive.fill.badge.xmark"
  }

  var metricsTitle: String {
    sharesAnonymousMetrics ? "Opted in" : "Not sharing"
  }

  var metricsSymbol: String {
    sharesAnonymousMetrics ? "checkmark.circle.fill" : "hand.raised.fill"
  }
}
