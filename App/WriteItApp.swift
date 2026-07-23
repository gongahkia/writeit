import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let runtime = AppRuntime()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    runtime.start()
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    runtime.capture.refreshAccessibility()
  }

  func applicationWillTerminate(_ notification: Notification) {
    runtime.stop()
  }
}

@main
struct WriteItApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup("WriteIt", id: "main") {
      ContentView(
        capture: appDelegate.runtime.capture,
        preferences: appDelegate.runtime.preferences,
        history: appDelegate.runtime.history
      )
      .frame(minWidth: 820, minHeight: 560)
    }
    .defaultSize(width: 1000, height: 680)

    Settings {
      SettingsView(
        capture: appDelegate.runtime.capture,
        preferences: appDelegate.runtime.preferences,
        history: appDelegate.runtime.history,
        models: appDelegate.runtime.models,
        recognitionCapabilities: appDelegate.runtime.recognition.capabilities
      )
      .frame(width: 860, height: 620)
    }

    MenuBarExtra("WriteIt", systemImage: "pencil.and.scribble") {
      MenuBarContent(
        capture: appDelegate.runtime.capture,
        preferences: appDelegate.runtime.preferences
      )
    }
    .menuBarExtraStyle(.menu)
  }
}
