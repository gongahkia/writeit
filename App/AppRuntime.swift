import Foundation

@MainActor
final class AppRuntime {
  let preferences: Preferences
  let history: HistoryStore
  let models: ModelStore
  let profiles: AppProfileStore
  let session: CaptureSession
  let recognition: RecognitionService
  let capture: CaptureCoordinator

  init(defaults: UserDefaults = .standard) {
    preferences = Preferences(defaults: defaults)
    history = HistoryStore()
    models = ModelStore()
    profiles = AppProfileStore(defaults: defaults)
    session = CaptureSession()
    recognition = RecognitionService()
    capture = CaptureCoordinator(
      preferences: preferences,
      history: history,
      session: session,
      shortcutMonitor: GlobalShortcutMonitor(),
      delivery: AccessibilityTextDelivery(),
      recognition: recognition,
      enhancer: AIEnhancer(),
      overlay: CaptureOverlayController.shared,
      loginItem: LoginItemService()
    )
  }

  func start() {
    AppLog.app.info("runtime_started")
    capture.start()
  }

  func stop() {
    AppLog.app.info("runtime_stopped")
    capture.stop()
  }
}
