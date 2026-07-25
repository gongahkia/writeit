import Foundation

enum AppProfileCreationError: LocalizedError, Equatable {
  case foregroundApplicationUnavailable

  var errorDescription: String? {
    switch self {
    case .foregroundApplicationUnavailable: "No foreground app is available for a profile."
    }
  }
}

@MainActor
final class CurrentAppProfileCreator {
  private let profiles: AppProfileStore
  private let foregroundApplicationResolver: any ForegroundApplicationBundleIdentifierResolving

  init(
    profiles: AppProfileStore,
    foregroundApplicationResolver: any ForegroundApplicationBundleIdentifierResolving
  ) {
    self.profiles = profiles
    self.foregroundApplicationResolver = foregroundApplicationResolver
  }

  func create() throws -> AppProfile {
    guard let bundleIdentifier = foregroundApplicationResolver.resolve() else {
      throw AppProfileCreationError.foregroundApplicationUnavailable
    }
    if let existing = profiles.profile(matching: bundleIdentifier, includingDisabled: true) {
      return existing
    }
    let profile = try AppProfile(bundleIdentifier: bundleIdentifier)
    try profiles.replaceProfiles(profiles.profiles + [profile])
    return profile
  }
}
