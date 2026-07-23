import AppKit
import Foundation

enum CaptureMode: String, CaseIterable, Codable, Identifiable {
  case toggle
  case penUpDelay
  case holdToCapture

  var id: String { rawValue }
  var title: String {
    switch self {
    case .toggle: "Toggle shortcut"
    case .penUpDelay: "Pen-up delay"
    case .holdToCapture: "Hold shortcut"
    }
  }
}

enum ResultMode: String, CaseIterable, Codable, Identifiable {
  case autoInsert
  case review
  case clipboard

  var id: String { rawValue }
  var title: String {
    switch self {
    case .autoInsert: "Auto insert + Undo"
    case .review: "Editable review"
    case .clipboard: "Clipboard only"
    }
  }
}

enum OutputStrategy: String, CaseIterable, Codable, Identifiable {
  case paste
  case accessibility
  case clipboard

  var id: String { rawValue }
  var title: String {
    switch self {
    case .paste: "Paste into captured field"
    case .accessibility: "Replace via Accessibility"
    case .clipboard: "Clipboard only"
    }
  }
}

enum HistoryMode: String, CaseIterable, Codable, Identifiable {
  case full
  case textOnly
  case off

  var id: String { rawValue }
  var title: String {
    switch self {
    case .full: "Text + ink history"
    case .textOnly: "Text history"
    case .off: "No history"
    }
  }
}

enum CapturePhase: Equatable {
  case idle
  case drawing
  case recognizing
  case reviewing
  case delivered(String)

  var isActive: Bool { self != .idle }
}

struct Shortcut: Codable, Hashable {
  var keyCode: UInt16
  var modifiers: UInt64

  static let `default` = Shortcut(
    keyCode: 13,
    modifiers: CGEventFlags.maskCommand.union(.maskShift).rawValue
  )

  var displayName: String {
    let flags = CGEventFlags(rawValue: modifiers)
    let prefix = [
      flags.contains(.maskControl) ? "⌃" : "",
      flags.contains(.maskAlternate) ? "⌥" : "",
      flags.contains(.maskShift) ? "⇧" : "",
      flags.contains(.maskCommand) ? "⌘" : "",
    ].joined()
    return prefix + KeyName.name(for: keyCode)
  }
}

enum KeyName {
  static func name(for keyCode: UInt16) -> String {
    let names: [UInt16: String] = [
      0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
      11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
      34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 49: "Space", 36: "↩",
    ]
    return names[keyCode] ?? "Key \(keyCode)"
  }
}

struct InkPoint: Codable, Hashable {
  var x: CGFloat
  var y: CGFloat
  var pressure: CGFloat
  var timestamp: TimeInterval
}

struct InkStroke: Identifiable, Codable, Hashable {
  var id = UUID()
  var points: [InkPoint]
}

struct HistoryEntry: Identifiable, Codable, Hashable {
  var id = UUID()
  var createdAt = Date()
  var text: String
  var strokes: [InkStroke]?
  var source: String
}
