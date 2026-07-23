import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    AppModel.shared.start()
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    AppModel.shared.refreshAccessibility()
  }
}

@main
struct WriteItApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup("WriteIt", id: "main") {
      ContentView(model: AppModel.shared)
        .frame(minWidth: 820, minHeight: 560)
    }
    .defaultSize(width: 1000, height: 680)

    Settings {
      SettingsView(model: AppModel.shared)
        .frame(width: 560, height: 480)
    }

    MenuBarExtra("WriteIt", systemImage: "pencil.and.scribble") {
      MenuBarContent(model: AppModel.shared)
    }
    .menuBarExtraStyle(.menu)
  }
}
