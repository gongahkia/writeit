import SwiftUI

private enum MainSection: String, CaseIterable, Identifiable {
  case capture
  case history
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
  var icon: String { self == .capture ? "pencil.and.scribble" : "clock.arrow.circlepath" }
}

struct ContentView: View {
  @ObservedObject var model: AppModel
  @State private var section: MainSection? = .capture

  var body: some View {
    NavigationSplitView {
      List(selection: $section) {
        ForEach(MainSection.allCases) { item in
          Label(item.title, systemImage: item.icon).tag(Optional(item))
        }
      }
      .listStyle(.sidebar)
      .navigationTitle("WriteIt")
    } detail: {
      switch section ?? .capture {
      case .capture: CaptureDashboard(model: model)
      case .history: CaptureHistoryView(history: model.history, preferences: model.preferences, onCleanup: model.cleanupHistory)
      }
    }
  }
}

private struct CaptureDashboard: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Write anywhere").font(.system(size: 30, weight: .bold))
        Text("Handwrite a thought, then send it to the text field you were using.")
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 16) {
        Button(action: model.beginCapture) {
          Label("Start writing", systemImage: "pencil.tip")
        }
        .buttonStyle(.borderedProminent)
        Text(model.preferences.shortcut.displayName).font(.title3.monospaced()).foregroundStyle(.secondary)
      }
      .controlSize(.large)

      GroupBox("Status") {
        HStack(spacing: 10) {
          Image(systemName: model.accessibilityGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
            .foregroundStyle(model.accessibilityGranted ? .green : .orange)
          Text(model.statusMessage)
          Spacer()
          if !model.accessibilityGranted {
            Button("Enable Accessibility", action: model.requestAccessibility)
          }
        }
        .padding(4)
      }

      GroupBox("How it works") {
        VStack(alignment: .leading, spacing: 10) {
          Label("Press your shortcut to open the writing surface.", systemImage: "1.circle")
          Label("Write with a mouse or tablet stylus.", systemImage: "2.circle")
          Label("Press the shortcut again to recognize and insert.", systemImage: "3.circle")
        }
        .foregroundStyle(.secondary)
        .padding(4)
      }
      Spacer()
    }
    .padding(32)
    .navigationTitle("Capture")
  }
}

struct MenuBarContent: View {
  @ObservedObject var model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Start writing") { model.beginCapture() }
    Button("Open WriteIt") {
      NSApp.activate(ignoringOtherApps: true)
      openWindow(id: "main")
    }
    Divider()
    Text(model.statusMessage).lineLimit(1)
    Divider()
    SettingsLink { Text("Settings…") }
    Button("Quit WriteIt") { NSApp.terminate(nil) }
  }
}
