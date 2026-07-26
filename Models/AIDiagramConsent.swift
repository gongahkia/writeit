import Foundation

enum AIDiagramDisclosure {
  static let version = 1
  static let message = "AI diagram fallback sends the rendered capture image and recognized text to the configured endpoint and model when local translation does not produce a diagram."
}

struct AIDiagramConsent: Codable, Sendable, Equatable {
  let disclosureVersion: Int

  init(disclosureVersion: Int = AIDiagramDisclosure.version) {
    self.disclosureVersion = disclosureVersion
  }

  var allowsAIDiagramTranslation: Bool { disclosureVersion == AIDiagramDisclosure.version }
}
