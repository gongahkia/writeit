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

enum ClipboardHandling: String, Codable, Equatable {
  case leaveRecognizedText
  case restorePrevious
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
  case opening
  case drawing
  case recognizing
  case reviewing
  case delivering
  case delivered(String)
  case failed(String)
  case dismissing

  var isActive: Bool { self != .idle }

  private var kind: Kind {
    switch self {
    case .idle: .idle
    case .opening: .opening
    case .drawing: .drawing
    case .recognizing: .recognizing
    case .reviewing: .reviewing
    case .delivering: .delivering
    case .delivered: .delivered
    case .failed: .failed
    case .dismissing: .dismissing
    }
  }

  func allowsTransition(to next: CapturePhase) -> Bool {
    switch (kind, next.kind) {
    case (.idle, .opening),
      (.opening, .drawing), (.opening, .dismissing),
      (.drawing, .recognizing), (.drawing, .dismissing),
      (.recognizing, .reviewing), (.recognizing, .delivering), (.recognizing, .failed),
      (.recognizing, .dismissing),
      (.reviewing, .delivering), (.reviewing, .dismissing),
      (.delivering, .delivered), (.delivering, .dismissing),
      (.delivered, .dismissing),
      (.failed, .drawing), (.failed, .dismissing),
      (.dismissing, .idle):
      true
    default:
      false
    }
  }

  private enum Kind {
    case idle
    case opening
    case drawing
    case recognizing
    case reviewing
    case delivering
    case delivered
    case failed
    case dismissing
  }
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

enum InkInputSource: String, Codable, Hashable {
  case mouse
  case stylus
}

struct InkPoint: Codable, Hashable {
  var x: CGFloat
  var y: CGFloat
  var pressure: CGFloat
  var timestamp: TimeInterval
  var inputSource: InkInputSource

  init(
    x: CGFloat,
    y: CGFloat,
    pressure: CGFloat,
    timestamp: TimeInterval,
    inputSource: InkInputSource = .mouse
  ) {
    self.x = x
    self.y = y
    self.pressure = pressure
    self.timestamp = timestamp
    self.inputSource = inputSource
  }

  private enum CodingKeys: String, CodingKey {
    case x
    case y
    case pressure
    case timestamp
    case inputSource
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    x = try container.decode(CGFloat.self, forKey: .x)
    y = try container.decode(CGFloat.self, forKey: .y)
    pressure = try container.decode(CGFloat.self, forKey: .pressure)
    timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
    inputSource = try container.decodeIfPresent(InkInputSource.self, forKey: .inputSource) ?? .mouse
  }
}

struct InkStyle: Equatable, Sendable {
  static let `default` = InkStyle(baseWidth: 4, pressureSensitivity: 0.6, smoothing: 0.25)

  var baseWidth: Double
  var pressureSensitivity: Double
  var smoothing: Double

  func lineWidth(for pressure: CGFloat, scale: CGFloat = 1) -> CGFloat {
    let normalizedPressure = min(max(pressure, 0), 1)
    let adjustment = 1 + (normalizedPressure - 0.5) * 2 * CGFloat(pressureSensitivity)
    return max(1, CGFloat(baseWidth) * scale * adjustment)
  }

  func smoothed(_ point: InkPoint, after previous: InkPoint) -> InkPoint {
    let weight = min(max(smoothing, 0), 1) * 0.75
    return InkPoint(
      x: previous.x + (point.x - previous.x) * (1 - weight),
      y: previous.y + (point.y - previous.y) * (1 - weight),
      pressure: previous.pressure + (point.pressure - previous.pressure) * (1 - weight),
      timestamp: point.timestamp
    )
  }
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
