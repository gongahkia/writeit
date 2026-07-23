import AppKit
import ApplicationServices

@MainActor
struct TargetReference {
  let element: AXUIElement
  let pid: pid_t
  let bundleIdentifier: String?
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

  func deliver(_ request: DeliveryRequest) -> DeliveryOutcome {
    AppLog.delivery.info(
      "delivery_requested strategy=\(request.strategy.rawValue, privacy: .public) target_available=\(request.target != nil, privacy: .public)"
    )
    guard copy(request.text) else { return .failed(.clipboardWriteFailed) }
    guard request.strategy != .clipboard else { return .clipboard }
    guard let target = request.target else { return .clipboardFallback(.targetUnavailable) }
    if let failure = targetFailure(target) { return .clipboardFallback(failure) }
    lastTarget = target
    guard activate(target) else { return .clipboardFallback(.activationFailed) }
    switch request.strategy {
    case .paste:
      return postKey(code: 9, flags: .maskCommand)
        ? .pasted(request.clipboardHandling)
        : .failed(.pasteEventUnavailable)
    case .accessibility:
      let result = AXUIElementSetAttributeValue(
        target.element,
        kAXSelectedTextAttribute as CFString,
        request.text as CFTypeRef
      )
      return result == .success
        ? .accessibilityInserted
        : .failed(.accessibilityInsertionFailed)
    case .clipboard:
      return .clipboard
    }
  }

  func undo() {
    guard let lastTarget, targetFailure(lastTarget) == nil else { return }
    _ = activate(lastTarget)
    _ = postKey(code: 6, flags: .maskCommand)
    AppLog.delivery.info("delivery_undo_requested")
  }

  private func isEditable(_ element: AXUIElement) -> Bool {
    var isSettable = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(
      element,
      kAXSelectedTextAttribute as CFString,
      &isSettable
    ) == .success && isSettable.boolValue
  }

  private func targetFailure(_ target: TargetReference) -> DeliveryFailure? {
    guard NSRunningApplication(processIdentifier: target.pid) != nil else {
      return .targetAppNotRunning
    }
    guard isEditable(target.element) else { return .targetNotEditable }
    return nil
  }

  private func copy(_ text: String) -> Bool {
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(text, forType: .string)
  }

  private func activate(_ target: TargetReference) -> Bool {
    NSRunningApplication(processIdentifier: target.pid)?.activate(options: []) ?? false
  }

  private func postKey(code: CGKeyCode, flags: CGEventFlags) -> Bool {
    let source = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    guard let down, let up else { return false }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return true
  }
}
