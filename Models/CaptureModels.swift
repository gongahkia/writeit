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

struct PenUpSubmissionEligibility {
  let taskID: UUID
  let strokeCount: Int

  func allowsSubmission(
    activeTaskID: UUID?,
    isCancelled: Bool,
    phase: CapturePhase,
    strokeCount: Int
  ) -> Bool {
    taskID == activeTaskID && isCancelled == false && phase == .drawing
      && self.strokeCount == strokeCount
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
    ShortcutDisplayRenderer.displayName(for: self)
  }
}

enum ShortcutDisplayRenderer {
  typealias KeyNameResolver = (UInt16) -> String?

  static func displayName(
    for shortcut: Shortcut,
    keyName: KeyNameResolver = KeyboardLayoutKeyRenderer.name(for:)
  ) -> String {
    let flags = CGEventFlags(rawValue: shortcut.modifiers)
    let prefix = [
      flags.contains(.maskControl) ? "⌃" : "",
      flags.contains(.maskAlternate) ? "⌥" : "",
      flags.contains(.maskShift) ? "⇧" : "",
      flags.contains(.maskCommand) ? "⌘" : "",
    ].joined()
    return prefix + (keyName(shortcut.keyCode) ?? "Key \(shortcut.keyCode)")
  }
}

enum CaptureCommand: Equatable {
  case cancel
  case clear
  case confirm
  case shortcut(ShortcutEvent)
}

enum CaptureKeyboardCommandResolver {
  private static let relevantModifiers = CGEventFlags.maskCommand.union(.maskShift).union(
    .maskAlternate).union(.maskControl)

  static func resolve(
    keyCode: UInt16,
    modifiers: UInt64,
    isAutorepeat: Bool,
    shortcut: Shortcut,
    event: ShortcutEvent
  ) -> CaptureCommand? {
    let relevant = CGEventFlags(rawValue: modifiers).intersection(relevantModifiers).rawValue
    if event == .up {
      return matchesShortcut(keyCode: keyCode, modifiers: relevant, shortcut: shortcut)
        ? .shortcut(event)
        : nil
    }
    guard isAutorepeat == false else { return nil }
    switch (keyCode, relevant) {
    case (53, 0): return .cancel
    case (36, 0), (76, 0): return .confirm
    case (51, CGEventFlags.maskCommand.rawValue): return .clear
    default:
      return matchesShortcut(keyCode: keyCode, modifiers: relevant, shortcut: shortcut)
        ? .shortcut(event)
        : nil
    }
  }

  private static func matchesShortcut(keyCode: UInt16, modifiers: UInt64, shortcut: Shortcut) -> Bool {
    keyCode == shortcut.keyCode && modifiers == shortcut.modifiers
  }
}

enum InkInputSource: String, Codable, Hashable {
  case mouse
  case stylus
}

enum InkInputNormalizer {
  static func source(for device: NSEvent.PointingDeviceType) -> InkInputSource {
    switch device {
    case .pen, .eraser: .stylus
    case .unknown, .cursor: .mouse
    @unknown default: .mouse
    }
  }

  static func pressure(_ value: CGFloat) -> CGFloat { min(max(value, 0.5), 1) }
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

enum CanvasCoordinateTransformer {
  static func resize(_ point: InkPoint, from sourceSize: CGSize, to targetSize: CGSize) -> InkPoint {
    guard sourceSize.width > 0, sourceSize.height > 0 else { return point }
    return InkPoint(
      x: point.x * targetSize.width / sourceSize.width,
      y: point.y * targetSize.height / sourceSize.height,
      pressure: point.pressure,
      timestamp: point.timestamp,
      inputSource: point.inputSource
    )
  }

  static func renderPoint(_ point: InkPoint, canvasSize: CGSize, outputSize: CGSize) -> CGPoint {
    CGPoint(
      x: point.x * outputSize.width / canvasSize.width,
      y: outputSize.height - point.y * outputSize.height / canvasSize.height
    )
  }
}

enum InkRasterLayout {
  static let logicalWidth: CGFloat = 1536
  static let backingScale: CGFloat = 2

  static func outputSize(for canvasSize: CGSize) -> CGSize {
    CGSize(
      width: logicalWidth,
      height: max(512, logicalWidth * canvasSize.height / canvasSize.width)
    )
  }

  static func pixelSize(for canvasSize: CGSize) -> (width: Int, height: Int) {
    let output = outputSize(for: canvasSize)
    return (
      Int((output.width * backingScale).rounded(.up)),
      Int((output.height * backingScale).rounded(.up))
    )
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
      timestamp: point.timestamp,
      inputSource: point.inputSource
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
