import Foundation

@MainActor
protocol RecognitionBackendSelecting: AnyObject {
  var availableBackends: [RecognitionBackendCapabilities] { get }
  func recognizer(for identifier: String) throws -> any TextRecognizing
}

@MainActor
final class RecognitionBackendRegistry: RecognitionBackendSelecting {
  private let localRecognizer: any TextRecognizing
  private let cloudProviders: CloudOCRProviderStore

  init(localRecognizer: any TextRecognizing, cloudProviders: CloudOCRProviderStore) {
    self.localRecognizer = localRecognizer
    self.cloudProviders = cloudProviders
  }

  var availableBackends: [RecognitionBackendCapabilities] {
    var backends: [RecognitionBackendCapabilities] = []
    if case .available = localRecognizer.capabilities.availability {
      backends.append(localRecognizer.capabilities)
    }
    backends.append(contentsOf: CloudOCRProvider.allCases.compactMap { provider in
      cloudProviders.isSelectable(provider) ? provider.capabilities : nil
    })
    return backends.sorted { $0.identifier < $1.identifier }
  }

  func recognizer(for identifier: String) throws -> any TextRecognizing {
    if identifier == localRecognizer.capabilities.identifier,
      case .available = localRecognizer.capabilities.availability
    {
      return localRecognizer
    }
    guard availableBackends.contains(where: { $0.identifier == identifier }) else {
      throw RecognitionError.unavailable("The selected OCR provider is unavailable.")
    }
    return try cloudProviders.recognizer(for: identifier)
  }
}
