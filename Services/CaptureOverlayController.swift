import AppKit
import SwiftUI

@MainActor
final class CaptureOverlayController: CaptureOverlayPresenting {
  static let shared = CaptureOverlayController()
  private var panel: NSPanel?

  func present(session: CaptureSession, model: AppModel) {
    let panel = panel ?? makePanel()
    let screen = NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? .zero
    panel.setFrame(screen, display: true)
    panel.contentView = NSHostingView(rootView: CaptureOverlayView(session: session, model: model))
    panel.orderFrontRegardless()
  }

  func dismiss() { panel?.orderOut(nil) }

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
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    panel.hidesOnDeactivate = false
    self.panel = panel
    return panel
  }
}
