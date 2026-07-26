import AppKit
import Foundation

enum UITestConfiguration {
  static var isEnabled: Bool {
    ProcessInfo.processInfo.environment["WRITEIT_UI_TESTING"] == "1"
  }

  static func defaults(fallback: UserDefaults) -> UserDefaults {
    guard isEnabled, let defaults = UserDefaults(suiteName: "com.gongahkia.writeit.ui-tests") else {
      return fallback
    }
    if ProcessInfo.processInfo.environment["WRITEIT_UI_RESET"] == "1" {
      defaults.removePersistentDomain(forName: "com.gongahkia.writeit.ui-tests")
    }
    return defaults
  }
}

actor UITestRecognitionBackend: TextRecognizing {
  nonisolated let capabilities = RecognitionBackendCapabilities(
    identifier: "apple-vision",
    displayName: "Apple Vision",
    supportedLanguages: Set(RecognitionLanguage.allCases),
    isLocal: true,
    supportsStreaming: false,
    availability: .available
  )

  func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult {
    RecognitionResult(text: "UI test capture", confidence: 1, backendID: "apple-vision", languageResolution: .identity(request.language))
  }
}

@MainActor
final class UITestAccessibilityDelivery: AccessibilityDelivering {
  var isTrusted: Bool { true }

  func requestTrust() {}
  func captureTarget() -> TargetReference? { nil }
  func clearCapturedTarget() {}
  func deliver(_ request: DeliveryRequest) async -> DeliveryOutcome {
    .clipboardFallback(.targetUnavailable)
  }
  func undo() {}
}

final class UITestShortcutMonitor: GlobalShortcutMonitoring {
  func start(shortcut: Shortcut, handler: @escaping (CaptureCommand) -> Void) {}
  func stop() {}
}
