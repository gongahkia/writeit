import SwiftUI

private enum MainSection: String, CaseIterable, Identifiable {
  case capture
  case history
  case models
  case cleanup
  case privacy

  var id: String { rawValue }
  var title: String { rawValue.capitalized }
  var icon: String {
    switch self {
    case .capture: "pencil.and.scribble"
    case .history: "clock.arrow.circlepath"
    case .models: "cpu"
    case .cleanup: "sparkles"
    case .privacy: "lock.shield"
    }
  }
}

struct ContentView: View {
  @ObservedObject var capture: CaptureCoordinator
  @ObservedObject var preferences: Preferences
  @ObservedObject var onboarding: OnboardingStore
  @ObservedObject var history: HistoryStore
  @ObservedObject var models: ModelStore
  @ObservedObject var dataDeletion: LocalDataDeletionController
  @ObservedObject var diagnostics: DiagnosticEventStore
  @ObservedObject var metrics: AnonymousMetricsQueue
  @ObservedObject var configurationImport: ConfigurationImportController
  @ObservedObject var cloudProviders: CloudOCRProviderStore
  @ObservedObject var profiles: AppProfileStore
  let profileCreator: CurrentAppProfileCreator
  let recognitionRegistry: RecognitionBackendRegistry
  @State private var section: MainSection = .capture

  var body: some View {
    if onboarding.isActive {
      OnboardingView(onboarding: onboarding)
    } else {
      mainContent
    }
  }

  private var mainContent: some View {
    NavigationSplitView {
      List(selection: $section) {
        ForEach(MainSection.allCases) { item in
          Label(item.title, systemImage: item.icon).tag(item)
        }
      }
      .listStyle(.sidebar)
      .navigationTitle("WriteIt")
    } detail: {
      switch section {
      case .capture: CaptureDashboard(capture: capture, preferences: preferences)
      case .history:
        CaptureHistoryView(
          history: history, preferences: preferences, onCleanup: capture.cleanupHistory,
          onRetryCapture: capture.retryCapture)
      case .models:
        ModelCatalogView(
          preferences: preferences,
          cloudProviders: cloudProviders,
          profiles: profiles,
          profileCreator: profileCreator,
          registry: recognitionRegistry
        )
      case .cleanup:
        CleanupSettingsView(capture: capture, preferences: preferences)
      case .privacy:
        PrivacySettingsView(
          capture: capture,
          preferences: preferences,
          history: history,
          dataDeletion: dataDeletion,
          diagnostics: diagnostics,
          metrics: metrics,
          configurationImport: configurationImport,
          profiles: profiles,
          cloudProviders: cloudProviders
        )
      }
    }
  }
}

private struct CaptureDashboard: View {
  @ObservedObject var capture: CaptureCoordinator
  @ObservedObject var preferences: Preferences

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Write anywhere").font(.system(size: 30, weight: .bold))
        Text("Handwrite a thought, then send it to the text field you were using.")
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 16) {
        Button(action: capture.beginCapture) {
          Label("Start writing", systemImage: "pencil.tip")
        }
        .buttonStyle(.borderedProminent)
        Text(preferences.shortcut.displayName).font(.title3.monospaced()).foregroundStyle(
          .secondary)
      }
      .controlSize(.large)

      GroupBox("Status") {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 10) {
            Image(
              systemName: capture.accessibilityGranted
                ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
            )
            .foregroundStyle(capture.accessibilityGranted ? .green : .orange)
            Text(capture.statusMessage)
            Spacer()
            if !capture.accessibilityGranted {
              Button("Enable Accessibility", action: capture.requestAccessibility)
            }
          }
          if let error = capture.error {
            CaptureErrorBanner(error: error, dismiss: capture.clearError)
          }
          if let error = preferences.error {
            CaptureErrorBanner(error: error, dismiss: preferences.clearError)
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
  @ObservedObject var capture: CaptureCoordinator
  @ObservedObject var preferences: Preferences
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Start writing") { capture.beginCapture() }
    Button("Open WriteIt") {
      NSApp.activate(ignoringOtherApps: true)
      openWindow(id: "main")
    }
    Divider()
    Text(capture.statusMessage).lineLimit(1)
    Divider()
    Button("Quit WriteIt") { NSApp.terminate(nil) }
  }
}
