import XCTest
@testable import WriteIt

final class WriteItTests: XCTestCase {
  func testNormalizesWhitespaceAndUnicode() {
    XCTAssertEqual(TextSanitizer.normalize("  cafe\u{301}\n\n  hello   world  "), "café hello world")
  }

  func testShortcutRoundTrip() throws {
    let shortcut = Shortcut(keyCode: 13, modifiers: CGEventFlags.maskCommand.union(.maskShift).rawValue)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(shortcut))
    XCTAssertEqual(decoded, shortcut)
    XCTAssertEqual(decoded.displayName, "⇧⌘W")
  }

  func testHistoryEntryCanOmitInk() throws {
    let entry = HistoryEntry(text: "testing", strokes: nil, source: "Apple Vision")
    let decoded = try JSONDecoder().decode(HistoryEntry.self, from: JSONEncoder().encode(entry))
    XCTAssertNil(decoded.strokes)
    XCTAssertEqual(decoded.text, "testing")
  }

  @MainActor
  func testInkSessionRendersSubmittedStrokes() {
    let session = CaptureSession()
    session.begin(target: nil)
    session.canvasSize = CGSize(width: 300, height: 120)
    session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))
    XCTAssertNotNil(session.renderedImage())
  }
}
