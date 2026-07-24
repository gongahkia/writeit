import AppKit
import ApplicationServices

@MainActor
struct TargetReference {
  let element: AXUIElement
  let pid: pid_t
  let bundleIdentifier: String?
  let displayID: UInt32?
}

enum CapturedTargetValidator {
  static func failure(isApplicationRunning: Bool, isEditable: Bool) -> DeliveryFailure? {
    guard isApplicationRunning else { return .targetAppNotRunning }
    guard isEditable else { return .targetNotEditable }
    return nil
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
      bundleIdentifier: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
      displayID: displayID(for: element)
    )
  }

  func clearCapturedTarget() {
    lastTarget = nil
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

  private func displayID(for element: AXUIElement) -> UInt32? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
      let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    let positionValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(positionValue) == .cgPoint else { return nil }
    var position = CGPoint.zero
    guard AXValueGetValue(positionValue, .cgPoint, &position) else { return nil }
    let displays = NSScreen.screens.compactMap { screen -> CaptureDisplay? in
      guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
      else { return nil }
      return CaptureDisplay(id: id.uint32Value, frame: screen.frame)
    }
    return CaptureDisplaySelector.sourceDisplayID(
      accessibilityPosition: position,
      displays: displays
    )
  }

  private func targetFailure(_ target: TargetReference) -> DeliveryFailure? {
    CapturedTargetValidator.failure(
      isApplicationRunning: NSRunningApplication(processIdentifier: target.pid) != nil,
      isEditable: isEditable(target.element)
    )
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
