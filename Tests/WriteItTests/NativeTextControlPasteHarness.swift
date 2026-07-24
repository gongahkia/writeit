import AppKit

@MainActor
final class NativeTextControlPasteHarness {
  private let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
  private let textView = NSTextView(frame: .zero)

  init(text: String, selection: NSRange) {
    textView.isEditable = true
    textView.string = text
    textView.setSelectedRange(selection)
  }

  var text: String { textView.string }

  func paste(_ value: String) -> Bool {
    pasteboard.clearContents()
    guard pasteboard.setString(value, forType: .string) else { return false }
    return textView.readSelection(from: pasteboard)
  }
}
