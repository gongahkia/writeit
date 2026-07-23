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
    runtime.model.refreshAccessibility()
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
      ContentView(model: appDelegate.runtime.model)
        .frame(minWidth: 820, minHeight: 560)
    }
    .defaultSize(width: 1000, height: 680)

    Settings {
      SettingsView(model: appDelegate.runtime.model)
        .frame(width: 860, height: 620)
    }

    MenuBarExtra("WriteIt", systemImage: "pencil.and.scribble") {
      MenuBarContent(model: appDelegate.runtime.model)
    }
    .menuBarExtraStyle(.menu)
  }
}
