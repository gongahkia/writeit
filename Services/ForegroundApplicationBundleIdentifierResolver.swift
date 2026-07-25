import AppKit

@MainActor
protocol ForegroundApplicationBundleIdentifierResolving: AnyObject {
  func resolve() -> String?
}

@MainActor
final class ForegroundApplicationBundleIdentifierResolver:
  ForegroundApplicationBundleIdentifierResolving
{
  private let frontmostBundleIdentifier: () -> String?

  init(frontmostBundleIdentifier: @escaping () -> String? = {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier
  }) {
    self.frontmostBundleIdentifier = frontmostBundleIdentifier
  }

  func resolve() -> String? {
    guard let bundleIdentifier = frontmostBundleIdentifier(), bundleIdentifier.isEmpty == false
    else { return nil }
    return bundleIdentifier
  }
}
