import AppKit
import SwiftUI

struct CaptureSettingsView: View {
  @ObservedObject var capture: CaptureCoordinator
  @ObservedObject private var preferences: Preferences
  @State private var shortcutValidationMessage: String?

  init(capture: CaptureCoordinator, preferences: Preferences) {
    self.capture = capture
    _preferences = ObservedObject(wrappedValue: preferences)
  }

  var body: some View {
    Form {
      Section("Shortcut") {
        HStack {
          Text("Capture shortcut")
          Spacer()
          ShortcutRecorder(
            shortcut: $preferences.shortcut,
            validationMessage: $shortcutValidationMessage
          )
        }
        if let shortcutValidationMessage {
          Text(shortcutValidationMessage).font(.caption).foregroundStyle(.red)
        }
        Picker("Capture mode", selection: $preferences.captureMode) {
          ForEach(CaptureMode.allCases) { Text($0.title).tag($0) }
        }
        if preferences.captureMode == .penUpDelay {
          Slider(value: $preferences.penUpDelay, in: 0.5...3, step: 0.1) {
            Text("Pen-up delay")
          } minimumValueLabel: {
            Text("0.5s")
          } maximumValueLabel: {
            Text("3s")
          }
        }
        Picker("After recognition", selection: $preferences.resultMode) {
          ForEach(ResultMode.allCases) { Text($0.title).tag($0) }
        }
        Picker("Delivery", selection: $preferences.outputStrategy) {
          ForEach(OutputStrategy.allCases) { Text($0.title).tag($0) }
        }
        if preferences.outputStrategy == .paste {
          Picker("Clipboard after paste", selection: $preferences.clipboardHandling) {
            ForEach(ClipboardHandling.allCases) { Text($0.title).tag($0) }
          }
          Toggle("Verify paste when available", isOn: $preferences.verifyPasteDelivery)
        }
        Picker("Recognition language", selection: $preferences.recognitionLanguage) {
          ForEach(RecognitionLanguage.allCases) { Text($0.displayName).tag($0) }
        }
      }
      Section("Ink input") {
        Slider(value: $preferences.strokeWidth, in: 1...12, step: 0.5) {
          Text("Stroke width")
        } minimumValueLabel: {
          Text("Fine")
        } maximumValueLabel: {
          Text("Bold")
        }
        Slider(value: $preferences.pressureSensitivity, in: 0...1, step: 0.05) {
          Text("Pressure response")
        } minimumValueLabel: {
          Text("Fixed")
        } maximumValueLabel: {
          Text("Strong")
        }
        Slider(value: $preferences.strokeSmoothing, in: 0...1, step: 0.05) {
          Text("Stroke smoothing")
        } minimumValueLabel: {
          Text("Raw")
        } maximumValueLabel: {
          Text("Smooth")
        }
        InkStylePreview(style: preferences.inkStyle)
      }
      Section("Recognition replacements") {
        LiteralReplacementRulesSettingsView(preferences: preferences)
        Divider()
        RegexReplacementRulesSettingsView(preferences: preferences)
        Divider()
        ReplacementPreviewView(preferences: preferences)
        Divider()
        ReplacementRuleImportExportView(preferences: preferences)
      }
      Section("Permissions") {
        LabeledContent(
          "Accessibility", value: capture.accessibilityGranted ? "Enabled" : "Required")
        if !capture.accessibilityGranted {
          Button("Request Accessibility", action: capture.requestAccessibility)
        }
      }
    }
    .padding(20)
    .navigationTitle("Capture")
    .onChange(of: preferences.shortcut) { _, _ in capture.restartShortcutMonitor() }
  }
}

struct CleanupSettingsView: View {
  @ObservedObject var capture: CaptureCoordinator
  @ObservedObject var preferences: Preferences
  @State private var apiKey = ""
  @State private var keySaved = false
  @State private var connectionStatus: AICleanupConnectionStatus?

  var body: some View {
    Form {
      if let error = capture.error {
        Section("Recent error") {
          CaptureErrorBanner(error: error, dismiss: capture.clearError)
        }
      }
      if let error = preferences.error {
        Section("Recent error") {
          CaptureErrorBanner(error: error, dismiss: preferences.clearError)
        }
      }
      Section("OpenAI-compatible cleanup") {
        Toggle("Enable AI cleanup", isOn: $preferences.aiEnabled)
        TextField("Chat completions URL", text: $preferences.aiBaseURL)
        TextField("Model", text: $preferences.aiModel)
        SecureField("API key", text: $apiKey)
        HStack {
          Button("Save API key") {
            capture.saveAPIKey(apiKey)
            apiKey = ""
            keySaved = capture.hasAPIKey()
          }
          if keySaved || capture.hasAPIKey() {
            Text("Saved in Keychain").foregroundStyle(.secondary)
          }
        }
        Text("Connection testing sends only the API key to the derived models endpoint; it never sends recognized text.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Button("Test connection") {
          Task { connectionStatus = await capture.testAIConnection() }
        }
        if let connectionStatus {
          Text(connectionStatus.message).font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .padding(20)
    .navigationTitle("Cleanup")
  }
}

struct PrivacySettingsView: View {
  @ObservedObject var capture: CaptureCoordinator
  @ObservedObject var preferences: Preferences
  @ObservedObject var history: HistoryStore
  @ObservedObject var dataDeletion: LocalDataDeletionController
  @ObservedObject var diagnostics: DiagnosticEventStore
  @ObservedObject var metrics: AnonymousMetricsQueue
  @ObservedObject var configurationImport: ConfigurationImportController
  @ObservedObject var profiles: AppProfileStore
  @ObservedObject var cloudProviders: CloudOCRProviderStore
  @State private var deleteHistory = false
  @State private var deleteModels = false
  @State private var deleteDiagnostics = false
  @State private var deleteMetrics = false
  @State private var deleteCredentials = false
  @State private var showsDeletionConfirmation = false

  var body: some View {
    Form {
      if let error = history.error {
        Section("Recent error") {
          CaptureErrorBanner(error: error, dismiss: history.clearError)
        }
      }
      if let error = preferences.error {
        Section("Recent error") {
          CaptureErrorBanner(error: error, dismiss: preferences.clearError)
        }
      }
      if let error = diagnostics.error {
        Section("Recent error") {
          CaptureErrorBanner(error: error, dismiss: diagnostics.clearError)
        }
      }
      if let error = metrics.error {
        Section("Recent error") {
          CaptureErrorBanner(error: error, dismiss: metrics.clearError)
        }
      }
      Section("History") {
        Picker("Retain captures", selection: $preferences.historyMode) {
          ForEach(HistoryMode.allCases) { Text($0.title).tag($0) }
        }
        Text("History is encrypted locally. It is never uploaded for training.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Toggle("Auto-delete history", isOn: $preferences.historyAutoDelete)
      }
      Section("Diagnostics") {
        Toggle(
          "Do not retain diagnostic logs",
          isOn: Binding(
            get: { preferences.retainsLocalLogs == false },
            set: { preferences.retainsLocalLogs = !$0 }
          )
        )
        .onChange(of: preferences.retainsLocalLogs) { _, retainsLocalLogs in
          diagnostics.setRetainsLocalLogs(retainsLocalLogs)
        }
        Text("Turning this on immediately deletes local diagnostic events and prevents new events from being saved.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Section("Anonymous metrics") {
        Toggle("Share anonymous metrics", isOn: $preferences.allowsAnonymousMetrics)
          .onChange(of: preferences.allowsAnonymousMetrics) { _, allowsAnonymousMetrics in
            metrics.setConsent(allowsAnonymousMetrics)
          }
        Text("Optional fixed lifecycle codes are queued locally only. This build does not send metrics.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Section("Delete local data") {
        Toggle(isOn: $deleteHistory) {
          VStack(alignment: .leading) {
            Text(LocalDataCategory.history.title)
            Text(LocalDataCategory.history.detail).font(.caption).foregroundStyle(.secondary)
          }
        }
        Toggle(isOn: $deleteModels) {
          VStack(alignment: .leading) {
            Text(LocalDataCategory.models.title)
            Text(LocalDataCategory.models.detail).font(.caption).foregroundStyle(.secondary)
          }
        }
        Toggle(isOn: $deleteDiagnostics) {
          VStack(alignment: .leading) {
            Text(LocalDataCategory.diagnostics.title)
            Text(LocalDataCategory.diagnostics.detail).font(.caption).foregroundStyle(.secondary)
          }
        }
        Toggle(isOn: $deleteMetrics) {
          VStack(alignment: .leading) {
            Text(LocalDataCategory.metrics.title)
            Text(LocalDataCategory.metrics.detail).font(.caption).foregroundStyle(.secondary)
          }
        }
        Toggle(isOn: $deleteCredentials) {
          VStack(alignment: .leading) {
            Text(LocalDataCategory.credentials.title)
            Text(LocalDataCategory.credentials.detail).font(.caption).foregroundStyle(.secondary)
          }
        }
        Button("Delete selected data", role: .destructive, action: requestDeletion)
          .disabled(selectedDeletionCategories.isEmpty)
          .confirmationDialog(
            "Permanently delete selected local data?", isPresented: $showsDeletionConfirmation,
            titleVisibility: .visible
          ) {
            Button("Delete selected data", role: .destructive, action: deleteSelectedData)
          } message: {
            Text("This cannot be undone. Selected data never leaves this Mac during deletion.")
          }
        if dataDeletion.deletedCategories.isEmpty == false {
          Text("Deleted: \(dataDeletion.deletedCategories.map(\.title).joined(separator: ", ")).")
            .font(.caption).foregroundStyle(.secondary)
        }
        if let error = dataDeletion.error {
          CaptureErrorBanner(error: error, dismiss: dataDeletion.clearError)
        }
      }
      Section("Configuration") {
        ConfigurationExportView(
          preferences: preferences,
          profiles: profiles,
          cloudProviders: cloudProviders,
          importer: configurationImport
        )
      }
      Section("App") {
        Toggle("Launch at login", isOn: $preferences.launchAtLogin)
          .onChange(of: preferences.launchAtLogin) { _, _ in capture.updateLaunchAtLogin() }
      }
    }
    .padding(20)
    .navigationTitle("Privacy")
  }

  private var selectedDeletionCategories: Set<LocalDataCategory> {
    var categories: Set<LocalDataCategory> = []
    if deleteHistory { categories.insert(.history) }
    if deleteModels { categories.insert(.models) }
    if deleteDiagnostics { categories.insert(.diagnostics) }
    if deleteMetrics { categories.insert(.metrics) }
    if deleteCredentials { categories.insert(.credentials) }
    return categories
  }

  private func requestDeletion() { showsDeletionConfirmation = true }

  private func deleteSelectedData() {
    dataDeletion.delete(selectedDeletionCategories)
    for category in dataDeletion.deletedCategories { setSelected(false, for: category) }
  }

  private func setSelected(_ value: Bool, for category: LocalDataCategory) {
    switch category {
    case .history: deleteHistory = value
    case .models: deleteModels = value
    case .diagnostics: deleteDiagnostics = value
    case .metrics: deleteMetrics = value
    case .credentials: deleteCredentials = value
    }
  }
}

private struct ShortcutRecorder: NSViewRepresentable {
  @Binding var shortcut: Shortcut
  @Binding var validationMessage: String?

  func makeCoordinator() -> Coordinator {
    Coordinator(shortcut: $shortcut, validationMessage: $validationMessage)
  }
  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(
      title: shortcut.displayName, target: context.coordinator,
      action: #selector(Coordinator.beginRecording))
    button.bezelStyle = .rounded
    context.coordinator.button = button
    return button
  }

  func updateNSView(_ nsView: NSButton, context: Context) {
    nsView.title = context.coordinator.recording ? "Press shortcut…" : shortcut.displayName
  }

  static func dismantleNSView(_ nsView: NSButton, coordinator: Coordinator) {
    coordinator.stopRecording()
  }

  @MainActor
  final class Coordinator: NSObject {
    var shortcut: Binding<Shortcut>
    var validationMessage: Binding<String?>
    weak var button: NSButton?
    var recording = false
    private var monitor: Any?

    init(shortcut: Binding<Shortcut>, validationMessage: Binding<String?>) {
      self.shortcut = shortcut
      self.validationMessage = validationMessage
    }

    @objc func beginRecording() {
      stopRecording()
      recording = true
      button?.title = "Press shortcut…"
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self, self.recording else { return event }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isEmpty else { return event }
        var cgFlags: CGEventFlags = []
        if flags.contains(.command) { cgFlags.insert(.maskCommand) }
        if flags.contains(.option) { cgFlags.insert(.maskAlternate) }
        if flags.contains(.control) { cgFlags.insert(.maskControl) }
        if flags.contains(.shift) { cgFlags.insert(.maskShift) }
        let candidate = Shortcut(keyCode: event.keyCode, modifiers: cgFlags.rawValue)
        if let message = ShortcutConflictValidator.message(for: candidate) {
          self.validationMessage.wrappedValue = message
          self.stopRecording()
          return nil
        }
        self.validationMessage.wrappedValue = nil
        self.shortcut.wrappedValue = candidate
        self.stopRecording()
        self.button?.title = self.shortcut.wrappedValue.displayName
        return nil
      }
    }

    func stopRecording() {
      recording = false
      if let monitor {
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
      }
    }
  }
}
