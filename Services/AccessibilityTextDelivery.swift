import AppKit
import ApplicationServices

@MainActor
struct TargetReference {
  let element: AXUIElement
  let pid: pid_t
  let bundleIdentifier: String?
}

enum DeliveryOutcome: Equatable {
  case pasted
  case accessibilityInserted
  case clipboard
  case targetUnavailable
  case failed(String)

  var message: String {
    switch self {
    case .pasted: "Pasted into captured field"
    case .accessibilityInserted: "Inserted into captured field"
    case .clipboard: "Copied to clipboard"
    case .targetUnavailable: "Copied: captured field is unavailable"
    case .failed(let message): message
    }
  }
}

@MainActor
final class AccessibilityTextDelivery: AccessibilityDelivering {
  private var lastTarget: TargetReference?

  var isTrusted: Bool { AXIsProcessTrusted() }

  func requestTrust() {
    AXIsProcessTrustedWithOptions(
      ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary)
  }

  func captureTarget() -> TargetReference? {
    guard isTrusted else { return nil }
    let system = AXUIElementCreateSystemWide()
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value)
        == .success,
      let value
    else { return nil }
    let element = unsafeDowncast(value, to: AXUIElement.self)
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success, pid != 0,
      isEditable(element)
    else { return nil }
    return TargetReference(
      element: element,
      pid: pid,
      bundleIdentifier: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    )
  }

  func deliver(
    _ text: String,
    to target: TargetReference?,
    strategy: OutputStrategy
  ) -> DeliveryOutcome {
    copy(text)
    guard strategy != .clipboard else { return .clipboard }
    guard let target, isTargetAvailable(target) else { return .targetUnavailable }
    lastTarget = target
    activate(target)
    switch strategy {
    case .paste:
      postKey(code: 9, flags: .maskCommand)
      return .pasted
    case .accessibility:
      let result = AXUIElementSetAttributeValue(
        target.element,
        kAXSelectedTextAttribute as CFString,
        text as CFTypeRef
      )
      return result == .success
        ? .accessibilityInserted
        : .failed("Accessibility could not replace text in the captured field")
    case .clipboard:
      return .clipboard
    }
  }

  func undo() {
    guard let lastTarget, isTargetAvailable(lastTarget) else { return }
    activate(lastTarget)
    postKey(code: 6, flags: .maskCommand)
  }

  private func isEditable(_ element: AXUIElement) -> Bool {
    var isSettable = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(
      element,
      kAXSelectedTextAttribute as CFString,
      &isSettable
    ) == .success && isSettable.boolValue
  }

  private func isTargetAvailable(_ target: TargetReference) -> Bool {
    guard NSRunningApplication(processIdentifier: target.pid) != nil else { return false }
    return isEditable(target.element)
  }

  private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  private func activate(_ target: TargetReference) {
    NSRunningApplication(processIdentifier: target.pid)?.activate(options: [])
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
