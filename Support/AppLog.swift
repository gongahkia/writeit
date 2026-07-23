import Foundation
import OSLog

enum AppLog {
  private static let subsystem = Bundle.main.bundleIdentifier ?? "com.gongahkia.writeit"

  static let app = Logger(subsystem: subsystem, category: "app")
  static let capture = Logger(subsystem: subsystem, category: "capture")
  static let shortcut = Logger(subsystem: subsystem, category: "shortcut")
  static let recognition = Logger(subsystem: subsystem, category: "recognition")
  static let delivery = Logger(subsystem: subsystem, category: "delivery")
  static let history = Logger(subsystem: subsystem, category: "history")
  static let models = Logger(subsystem: subsystem, category: "models")
  static let cleanup = Logger(subsystem: subsystem, category: "cleanup")

  static func errorType(_ error: Error) -> String {
    String(reflecting: type(of: error))
  }
}
