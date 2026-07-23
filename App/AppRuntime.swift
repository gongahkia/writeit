import Foundation

@MainActor
final class AppRuntime {
  let model: AppModel

  init(defaults: UserDefaults = .standard) {
    let preferences = Preferences(defaults: defaults)
    let history = HistoryStore()
    let models = ModelStore()
    let session = CaptureSession()
    model = AppModel(
      preferences: preferences,
      history: history,
      models: models,
      session: session,
      shortcutMonitor: GlobalShortcutMonitor(),
      delivery: AccessibilityTextDelivery(),
      recognition: RecognitionService(),
      enhancer: AIEnhancer(),
      overlay: CaptureOverlayController.shared,
      loginItem: LoginItemService()
    )
  }

  func start() { model.start() }
  func stop() { model.stop() }
}
