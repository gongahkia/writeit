import AppKit

@MainActor
protocol AccessibilityDelivering: AnyObject {
  var isTrusted: Bool { get }
  func requestTrust()
  func captureTarget() -> TargetReference?
  func deliver(_ text: String, to target: TargetReference?, mode: ResultMode) -> DeliveryOutcome
  func undo()
}

protocol GlobalShortcutMonitoring: AnyObject {
  func start(shortcut: Shortcut, handler: @escaping (ShortcutEvent) -> Void)
  func stop()
}

protocol TextRecognizing: AnyObject {
  func recognize(image: NSImage) async -> OCRCandidate?
}

protocol TextEnhancing: AnyObject {
  func clean(_ text: String, preferences: Preferences) async -> String
  func saveAPIKey(_ value: String)
  func hasAPIKey() -> Bool
}

@MainActor
protocol CaptureOverlayPresenting: AnyObject {
  func present(session: CaptureSession, model: AppModel)
  func dismiss()
}

@MainActor
protocol LoginItemManaging: AnyObject {
  func update(enabled: Bool)
}
