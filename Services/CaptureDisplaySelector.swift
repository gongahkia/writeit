import Foundation

struct CaptureDisplay: Equatable {
  let id: UInt32
  let frame: CGRect
}

enum CaptureDisplaySelector {
  static func sourceDisplayID(
    accessibilityPosition: CGPoint?,
    displays: [CaptureDisplay]
  ) -> UInt32? {
    guard let accessibilityPosition, let primary = displays.first else { return nil }
    let appKitPosition = CGPoint(
      x: accessibilityPosition.x,
      y: primary.frame.maxY - accessibilityPosition.y
    )
    return displays.first(where: { $0.frame.contains(appKitPosition) })?.id
  }

  static func displayID(sourceDisplayID: UInt32?, displays: [CaptureDisplay]) -> UInt32? {
    guard !displays.isEmpty else { return nil }
    if let sourceDisplayID, displays.contains(where: { $0.id == sourceDisplayID }) {
      return sourceDisplayID
    }
    return displays[0].id
  }
}
