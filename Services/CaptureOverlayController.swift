import AppKit
import SwiftUI

enum CaptureOverlaySpacePolicy {
  static let collectionBehavior: NSWindow.CollectionBehavior = [
    .moveToActiveSpace,
    .fullScreenAuxiliary,
    .ignoresCycle,
  ]
}

@MainActor
final class CaptureOverlayController: CaptureOverlayPresenting {
  static let shared = CaptureOverlayController()
  private var panel: NSPanel?

  func present(session: CaptureSession, coordinator: CaptureCoordinator, preferences: Preferences) {
    let panel = panel ?? makePanel()
    panel.setFrame(displayFrame(for: session.target?.displayID), display: true)
    panel.contentView = NSHostingView(
      rootView: CaptureOverlayView(
        session: session,
        coordinator: coordinator,
        preferences: preferences
      ))
    panel.orderFrontRegardless()
  }

  func dismiss() { panel?.orderOut(nil) }

  private func displayFrame(for sourceDisplayID: UInt32?) -> CGRect {
    let screens = NSScreen.screens
    let displays = screens.compactMap { screen -> CaptureDisplay? in
      guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
      else { return nil }
      return CaptureDisplay(id: id.uint32Value, frame: screen.frame)
    }
    guard let displayID = CaptureDisplaySelector.displayID(
      sourceDisplayID: sourceDisplayID,
      displays: displays
    ) else { return .zero }
    return displays.first(where: { $0.id == displayID })?.frame ?? .zero
  }

  private func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .statusBar
    panel.collectionBehavior = CaptureOverlaySpacePolicy.collectionBehavior
    panel.hidesOnDeactivate = false
    self.panel = panel
    return panel
  }
}
