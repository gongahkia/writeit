import Foundation

enum ModelCompatibilityFailure: LocalizedError, Equatable {
  case requiresAppleSilicon
  case requiresMacOS(ModelMacOSVersion)
  case storageUnavailable
  case insufficientStorage(required: UInt64, available: UInt64)

  var errorDescription: String? {
    switch self {
    case .requiresAppleSilicon: "This model requires Apple Silicon."
    case .requiresMacOS(let version):
      "This model requires macOS \(version.major).\(version.minor).\(version.patch) or later."
    case .storageUnavailable: "WriteIt could not check available storage for this model."
    case .insufficientStorage: "There is not enough available storage to install this model."
    }
  }
}

struct ModelCompatibilityEnvironment: Sendable, Equatable {
  let isAppleSilicon: Bool
  let macOSVersion: ModelMacOSVersion
  let availableStorageBytes: UInt64?
}

enum ModelCompatibilityChecker {
  static let installHeadroomBytes: UInt64 = 512 * 1_024 * 1_024

  static func failure(
    for manifest: ModelManifest,
    environment: ModelCompatibilityEnvironment
  ) -> ModelCompatibilityFailure? {
    if manifest.requiresAppleSilicon && !environment.isAppleSilicon {
      return .requiresAppleSilicon
    }
    if environment.macOSVersion < manifest.minimumMacOSVersion {
      return .requiresMacOS(manifest.minimumMacOSVersion)
    }
    guard let available = environment.availableStorageBytes else {
      return .storageUnavailable
    }
    let required = requiredStorageBytes(for: manifest)
    return available >= required ? nil : .insufficientStorage(required: required, available: available)
  }

  static func requiredStorageBytes(for manifest: ModelManifest) -> UInt64 {
    let doubled = manifest.assetSizeBytes.multipliedReportingOverflow(by: 2)
    guard !doubled.overflow else { return .max }
    let total = doubled.partialValue.addingReportingOverflow(installHeadroomBytes)
    return total.overflow ? .max : total.partialValue
  }

  static func currentEnvironment(storageURL: URL) -> ModelCompatibilityEnvironment {
    let values = try? storageURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    let available = values?.volumeAvailableCapacityForImportantUsage.flatMap { $0 >= 0 ? UInt64($0) : nil }
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return ModelCompatibilityEnvironment(
      isAppleSilicon: {
        #if arch(arm64)
          true
        #else
          false
        #endif
      }(),
      macOSVersion: ModelMacOSVersion(
        major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion),
      availableStorageBytes: available
    )
  }
}
