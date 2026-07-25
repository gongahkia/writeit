import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticExportView: View {
  @ObservedObject var diagnostics: DiagnosticEventStore
  @State private var message: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .top) {
        Text("Export diagnostics").font(.subheadline)
        Spacer()
        Button("Export", systemImage: "square.and.arrow.up", action: exportDiagnostics)
          .buttonStyle(.bordered)
      }
      Text("Exports event codes and timestamps only. Text, ink, screenshots, identifiers, credentials, and other local data are excluded.")
        .font(.caption)
        .foregroundStyle(.secondary)
      if let message {
        Text(message).font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func exportDiagnostics() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "WriteItDiagnostics.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let archive = DiagnosticExportArchive(events: diagnostics.events)
      try DiagnosticExportFileStore.write(DiagnosticExportCodec.encode(archive), to: url)
      message = "Diagnostics exported."
    } catch {
      message = (error as? LocalizedError)?.errorDescription ?? "Diagnostic export could not be saved."
    }
  }
}
