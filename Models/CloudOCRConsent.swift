import Foundation

enum CloudOCRDisclosure {
  static let version = 1
  static let message = "Cloud OCR sends the capture image to the selected cloud provider for recognition."
}

struct CloudOCRConsent: Codable, Sendable, Equatable {
  let disclosureVersion: Int

  init(disclosureVersion: Int = CloudOCRDisclosure.version) {
    self.disclosureVersion = disclosureVersion
  }

  var allowsCloudOCR: Bool { disclosureVersion == CloudOCRDisclosure.version }
}
