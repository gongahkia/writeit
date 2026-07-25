import Foundation

struct CaptureReadiness: Equatable {
  let accessibilityGranted: Bool
  let selectedBackendID: String
  let selectedBackend: RecognitionBackendCapabilities?

  init(
    accessibilityGranted: Bool,
    selectedBackendID: String,
    availableBackends: [RecognitionBackendCapabilities]
  ) {
    self.accessibilityGranted = accessibilityGranted
    self.selectedBackendID = selectedBackendID
    selectedBackend = availableBackends.first { $0.identifier == selectedBackendID }
  }

  var canStartCapture: Bool { selectedBackend != nil }
  var isFullyReady: Bool { accessibilityGranted && canStartCapture }
}
