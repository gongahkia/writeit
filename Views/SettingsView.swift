import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: AppModel
  @ObservedObject private var preferences: Preferences
  @State private var apiKey = ""
  @State private var keySaved = false

  init(model: AppModel) {
    self.model = model
    _preferences = ObservedObject(wrappedValue: model.preferences)
  }

  var body: some View {
    TabView {
      Form {
        Section("Shortcut") {
          HStack { Text("Capture shortcut"); Spacer(); ShortcutRecorder(shortcut: $preferences.shortcut) }
          Picker("Capture mode", selection: $preferences.captureMode) {
            ForEach(CaptureMode.allCases) { Text($0.title).tag($0) }
          }
          if preferences.captureMode == .penUpDelay {
            Slider(value: $preferences.penUpDelay, in: 0.5...3, step: 0.1) { Text("Pen-up delay") } minimumValueLabel: { Text("0.5s") } maximumValueLabel: { Text("3s") }
          }
          Picker("After recognition", selection: $preferences.resultMode) {
            ForEach(ResultMode.allCases) { Text($0.title).tag($0) }
          }
        }
        Section("Permissions") {
          LabeledContent("Accessibility", value: model.accessibilityGranted ? "Enabled" : "Required")
          if !model.accessibilityGranted { Button("Request Accessibility", action: model.requestAccessibility) }
        }
      }
      .padding(20).tabItem { Label("Capture", systemImage: "pencil.and.scribble") }

      ModelCatalogView(model: model)
        .tabItem { Label("Models", systemImage: "cpu") }

      Form {
        Section("OpenAI-compatible cleanup") {
          Toggle("Enable AI cleanup", isOn: $preferences.aiEnabled)
          TextField("Chat completions URL", text: $preferences.aiBaseURL)
          TextField("Model", text: $preferences.aiModel)
          SecureField("API key", text: $apiKey)
          HStack {
            Button("Save API key") { model.saveAPIKey(apiKey); apiKey = ""; keySaved = model.hasAPIKey() }
            if keySaved || model.hasAPIKey() { Text("Saved in Keychain").foregroundStyle(.secondary) }
          }
        }
      }
      .padding(20).tabItem { Label("Cleanup", systemImage: "sparkles") }

      Form {
        Section("History") {
          Picker("Retain captures", selection: $preferences.historyMode) {
            ForEach(HistoryMode.allCases) { Text($0.title).tag($0) }
          }
          Text("History is encrypted locally. It is never uploaded for training.").font(.caption).foregroundStyle(.secondary)
          Toggle("Auto-delete history", isOn: $preferences.historyAutoDelete)
          Button("Delete all history", role: .destructive, action: model.history.clear)
        }
        Section("App") {
          Toggle("Launch at login", isOn: $preferences.launchAtLogin)
            .onChange(of: preferences.launchAtLogin) { _, _ in model.updateLaunchAtLogin() }
        }
      }
      .padding(20).tabItem { Label("Privacy", systemImage: "lock.shield") }
    }
    .onChange(of: preferences.shortcut) { _, _ in model.restartShortcutMonitor() }
  }
}

private struct ShortcutRecorder: NSViewRepresentable {
  @Binding var shortcut: Shortcut

  func makeCoordinator() -> Coordinator { Coordinator(shortcut: $shortcut) }
  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(title: shortcut.displayName, target: context.coordinator, action: #selector(Coordinator.beginRecording))
    button.bezelStyle = .rounded
    context.coordinator.button = button
    return button
  }

  func updateNSView(_ nsView: NSButton, context: Context) { nsView.title = context.coordinator.recording ? "Press shortcut…" : shortcut.displayName }

  final class Coordinator: NSObject {
    var shortcut: Binding<Shortcut>
    weak var button: NSButton?
    var recording = false
    private var monitor: Any?

    init(shortcut: Binding<Shortcut>) { self.shortcut = shortcut }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    @objc func beginRecording() {
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
        self.shortcut.wrappedValue = Shortcut(keyCode: event.keyCode, modifiers: cgFlags.rawValue)
        self.recording = false
        if let monitor = self.monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        self.button?.title = self.shortcut.wrappedValue.displayName
        return nil
      }
    }
  }
}
