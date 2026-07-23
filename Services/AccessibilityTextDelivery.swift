import AppKit
import ApplicationServices

struct TargetReference {
  let pid: pid_t
}

enum DeliveryOutcome: Equatable {
  case inserted
  case clipboard
  case unavailable

  var message: String {
    switch self {
    case .inserted: "Inserted"
    case .clipboard: "Copied to clipboard"
    case .unavailable: "Copied: no editable target"
    }
  }
}

final class AccessibilityTextDelivery {
  private var lastTarget: TargetReference?

  var isTrusted: Bool { AXIsProcessTrusted() }

  func requestTrust() {
    AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary)
  }

  func captureTarget() -> TargetReference? {
    guard isTrusted else { return nil }
    let system = AXUIElementCreateSystemWide()
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
          let element = value else { return nil }
    let focused = unsafeBitCast(element, to: AXUIElement.self)
    guard AXUIElementIsAttributeSettable(focused, kAXSelectedTextAttribute as CFString) else { return nil }
    var pid: pid_t = 0
    guard AXUIElementGetPid(focused, &pid) == .success, pid != 0 else { return nil }
    return TargetReference(pid: pid)
  }

  func deliver(_ text: String, to target: TargetReference?, mode: ResultMode) -> DeliveryOutcome {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    guard mode != .clipboard else { return .clipboard }
    guard let target else { return .unavailable }
    lastTarget = target
    activate(target)
    postKey(code: 9, flags: .maskCommand)
    return .inserted
  }

  func undo() {
    guard let lastTarget else { return }
    activate(lastTarget)
    postKey(code: 6, flags: .maskCommand)
  }

  private func activate(_ target: TargetReference) {
    NSRunningApplication(processIdentifier: target.pid)?.activate(options: [.activateIgnoringOtherApps])
  }

  private func postKey(code: CGKeyCode, flags: CGEventFlags) {
    let source = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    down?.flags = flags
    up?.flags = flags
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
  }
}
