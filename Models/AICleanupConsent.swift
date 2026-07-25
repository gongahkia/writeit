import Foundation

enum AICleanupDisclosure {
  static let version = 1
  static let message = "AI cleanup sends recognized text to the configured endpoint and model."
}

struct AICleanupConsent: Codable, Sendable, Equatable {
  let disclosureVersion: Int

  init(disclosureVersion: Int = AICleanupDisclosure.version) {
    self.disclosureVersion = disclosureVersion
  }

  var allowsAICleanup: Bool { disclosureVersion == AICleanupDisclosure.version }
}
