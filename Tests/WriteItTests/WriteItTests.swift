import AppKit
import CryptoKit
import Foundation
import Testing

@testable import WriteIt

struct TextSanitizerTests {
  @Test("normalizes whitespace and Unicode")
  func normalizesWhitespaceAndUnicode() {
    #expect(TextSanitizer.normalize("  cafe\u{301}\n\n  hello   world  ") == "café hello world")
  }
}

struct CaptureModelTests {
  @Test("shortcuts round-trip through storage")
  func shortcutsRoundTrip() throws {
    let shortcut = Shortcut(
      keyCode: 13, modifiers: CGEventFlags.maskCommand.union(.maskShift).rawValue)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(shortcut))
    #expect(decoded == shortcut)
    #expect(decoded.displayName == "⇧⌘W")
  }

  @Test("history entries may omit ink")
  func historyEntriesMayOmitInk() throws {
    let entry = HistoryEntry(text: "testing", strokes: nil, source: "Apple Vision")
    let decoded = try JSONDecoder().decode(HistoryEntry.self, from: JSONEncoder().encode(entry))
    #expect(decoded.strokes == nil)
    #expect(decoded.text == "testing")
  }

  @Test("ink sessions render submitted strokes") @MainActor
  func inkSessionsRenderSubmittedStrokes() {
    let session = CaptureSession()
    session.begin(target: nil)
    session.canvasSize = CGSize(width: 300, height: 120)
    session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))
    #expect(session.renderedImage() != nil)
  }
}

struct PreferencesTests {
  @Test("registers defaults and records current schema")
  func registersDefaultsAndRecordsCurrentSchema() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    #expect(preferences.historyAutoDelete)
    #expect(preferences.historyRetentionDays == 7)
    #expect(preferences.penUpDelay == 1.2)
    #expect(defaults.integer(forKey: "schemaVersion") == Preferences.currentSchemaVersion)
  }

  @Test("migrates invalid retention and delay values")
  func migratesInvalidRetentionAndDelayValues() {
    let defaults = makeDefaults()
    defaults.set(0, forKey: "historyRetentionDays")
    defaults.set(50.0, forKey: "penUpDelay")
    let preferences = Preferences(defaults: defaults)
    #expect(preferences.historyRetentionDays == 1)
    #expect(preferences.penUpDelay == 3)
  }
}

struct HistoryStoreTests {
  @Test("removes only entries older than the cutoff") @MainActor
  func removesOnlyEntriesOlderThanCutoff() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let history = HistoryStore(
      fileURL: directory.appendingPathComponent("history.sealed"), key: SymmetricKey(size: .bits256)
    )
    let old = HistoryEntry(
      createdAt: Date(timeIntervalSinceNow: -86_400 * 8), text: "old", strokes: nil,
      source: "Vision")
    let current = HistoryEntry(createdAt: Date(), text: "current", strokes: nil, source: "Vision")
    history.append(old)
    history.append(current)
    history.removeEntries(olderThan: Date(timeIntervalSinceNow: -86_400))
    #expect(history.entries.map(\.text) == ["current"])
  }
}

struct AppModelLifecycleTests {
  @Test("starts and stops shortcut monitoring with Accessibility") @MainActor
  func startsAndStopsShortcutMonitoringWithAccessibility() {
    let dependencies = TestDependencies(trusted: false)
    let model = dependencies.makeModel()
    model.start()
    #expect(dependencies.shortcutMonitor.starts == 0)
    dependencies.delivery.trusted = true
    model.refreshAccessibility()
    #expect(model.accessibilityGranted)
    #expect(dependencies.shortcutMonitor.starts == 1)
    dependencies.delivery.trusted = false
    model.refreshAccessibility()
    #expect(model.accessibilityGranted == false)
    #expect(dependencies.shortcutMonitor.stops >= 2)
    model.stop()
  }
}

private func makeDefaults() -> UserDefaults {
  let name = "WriteItTests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: name)!
  defaults.removePersistentDomain(forName: name)
  return defaults
}

@MainActor
private final class TestDependencies {
  let defaults = makeDefaults()
  let shortcutMonitor = TestShortcutMonitor()
  let delivery: TestDelivery
  let recognition = TestRecognition()
  let enhancer = TestEnhancer()
  let overlay = TestOverlay()
  let loginItem = TestLoginItem()
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)

  init(trusted: Bool) { delivery = TestDelivery(trusted: trusted) }

  func makeModel() -> AppModel {
    AppModel(
      preferences: Preferences(defaults: defaults),
      history: HistoryStore(
        fileURL: directory.appendingPathComponent("history.sealed"),
        key: SymmetricKey(size: .bits256)),
      models: ModelStore(
        modelsDirectory: directory.appendingPathComponent("models", isDirectory: true)),
      session: CaptureSession(),
      shortcutMonitor: shortcutMonitor,
      delivery: delivery,
      recognition: recognition,
      enhancer: enhancer,
      overlay: overlay,
      loginItem: loginItem
    )
  }
}

private final class TestShortcutMonitor: GlobalShortcutMonitoring {
  var starts = 0
  var stops = 0

  func start(shortcut: Shortcut, handler: @escaping (ShortcutEvent) -> Void) { starts += 1 }
  func stop() { stops += 1 }
}

@MainActor
private final class TestDelivery: AccessibilityDelivering {
  var trusted: Bool
  var isTrusted: Bool { trusted }

  init(trusted: Bool) { self.trusted = trusted }
  func requestTrust() {}
  func captureTarget() -> TargetReference? { nil }
  func deliver(_ text: String, to target: TargetReference?, mode: ResultMode) -> DeliveryOutcome {
    .clipboard
  }
  func undo() {}
}

private final class TestRecognition: TextRecognizing {
  func recognize(image: NSImage) async -> OCRCandidate? { nil }
}

private final class TestEnhancer: TextEnhancing {
  func clean(_ text: String, preferences: Preferences) async -> String { text }
  func saveAPIKey(_ value: String) {}
  func hasAPIKey() -> Bool { false }
}

@MainActor
private final class TestOverlay: CaptureOverlayPresenting {
  func present(session: CaptureSession, model: AppModel) {}
  func dismiss() {}
}

@MainActor
private final class TestLoginItem: LoginItemManaging {
  func update(enabled: Bool) {}
}
