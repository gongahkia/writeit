import AppKit
import ApplicationServices

@MainActor
struct TargetReference {
  let element: AXUIElement
  let pid: pid_t
  let bundleIdentifier: String?
  let displayID: UInt32?
}

enum PasteDeliveryVerifier {
  static func result(
    expectedText: String,
    selectedText: String?,
    value: String?
  ) -> PasteDeliveryVerification {
    if selectedText == expectedText || value?.contains(expectedText) == true { return .verified }
    if selectedText == nil && value == nil { return .unavailable }
    return .failed
  }
}

struct ClipboardSnapshot {
  let items: [[NSPasteboard.PasteboardType: Data]]
}

@MainActor
protocol ClipboardRestoreScheduling: AnyObject {
  func schedule(_ action: @escaping () -> Void)
}

@MainActor
final class DelayedClipboardRestoreScheduler: ClipboardRestoreScheduling {
  func schedule(_ action: @escaping () -> Void) {
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(150))
      guard Task.isCancelled == false else { return }
      action()
    }
  }
}

@MainActor
protocol TargetActivationWaiting: AnyObject {
  func waitForActivation(pid: pid_t, isActive: @escaping (pid_t) -> Bool) async -> Bool
}

@MainActor
final class BoundedTargetActivationWaiter: TargetActivationWaiting {
  func waitForActivation(pid: pid_t, isActive: @escaping (pid_t) -> Bool) async -> Bool {
    if isActive(pid) { return true }
    for _ in 0..<10 {
      do {
        try await Task.sleep(for: .milliseconds(50))
      } catch {
        return false
      }
      if isActive(pid) { return true }
    }
    return false
  }
}

@MainActor
protocol AccessibilityDeliveryOperating: AnyObject {
  func captureClipboard() -> ClipboardSnapshot
  func copy(_ text: String) -> Bool
  func clipboardChangeCount() -> Int
  func restoreClipboard(_ snapshot: ClipboardSnapshot) -> Bool
  func isApplicationRunning(pid: pid_t) -> Bool
  func isActive(pid: pid_t) -> Bool
  func isEditable(_ element: AXUIElement) -> Bool
  func activate(pid: pid_t) -> Bool
  func postCommand(keyCode: CGKeyCode) -> Bool
  func verifyPastedText(_ text: String, in element: AXUIElement) async -> PasteDeliveryVerification
  func replaceSelectedText(in element: AXUIElement, with text: String) -> Bool
}

@MainActor
final class SystemAccessibilityDeliveryOperations: AccessibilityDeliveryOperating {
  func captureClipboard() -> ClipboardSnapshot {
    ClipboardSnapshot(
      items: NSPasteboard.general.pasteboardItems?.map { item in
        var values: [NSPasteboard.PasteboardType: Data] = [:]
        for type in item.types {
          if let data = item.data(forType: type) { values[type] = data }
        }
        return values
      } ?? []
    )
  }

  func copy(_ text: String) -> Bool {
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(text, forType: .string)
  }

  func clipboardChangeCount() -> Int { NSPasteboard.general.changeCount }

  func restoreClipboard(_ snapshot: ClipboardSnapshot) -> Bool {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard snapshot.items.isEmpty == false else { return true }
    let items = snapshot.items.map { values in
      let item = NSPasteboardItem()
      for (type, data) in values { item.setData(data, forType: type) }
      return item
    }
    return pasteboard.writeObjects(items)
  }

  func isApplicationRunning(pid: pid_t) -> Bool {
    NSRunningApplication(processIdentifier: pid) != nil
  }

  func isActive(pid: pid_t) -> Bool {
    NSRunningApplication(processIdentifier: pid)?.isActive ?? false
  }

  func isEditable(_ element: AXUIElement) -> Bool {
    var isSettable = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(
      element,
      kAXSelectedTextAttribute as CFString,
      &isSettable
    ) == .success && isSettable.boolValue
  }

  func activate(pid: pid_t) -> Bool {
    NSRunningApplication(processIdentifier: pid)?.activate(options: []) ?? false
  }

  func postCommand(keyCode: CGKeyCode) -> Bool {
    let source = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    guard let down, let up else { return false }
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return true
  }

  func verifyPastedText(_ text: String, in element: AXUIElement) async -> PasteDeliveryVerification {
    do {
      try await Task.sleep(for: .milliseconds(150))
    } catch {
      return .unavailable
    }
    return PasteDeliveryVerifier.result(
      expectedText: text,
      selectedText: stringAttribute(kAXSelectedTextAttribute, in: element),
      value: stringAttribute(kAXValueAttribute, in: element)
    )
  }

  func replaceSelectedText(in element: AXUIElement, with text: String) -> Bool {
    AXUIElementSetAttributeValue(
      element,
      kAXSelectedTextAttribute as CFString,
      text as CFTypeRef
    ) == .success
  }

  private func stringAttribute(_ attribute: String, in element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
      let value
    else { return nil }
    return value as? String
  }
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
  private let operations: any AccessibilityDeliveryOperating
  private let clipboardRestoreScheduler: any ClipboardRestoreScheduling
  private let targetActivationWaiter: any TargetActivationWaiting

  init(
    operations: any AccessibilityDeliveryOperating = SystemAccessibilityDeliveryOperations(),
    clipboardRestoreScheduler: any ClipboardRestoreScheduling = DelayedClipboardRestoreScheduler(),
    targetActivationWaiter: any TargetActivationWaiting = BoundedTargetActivationWaiter()
  ) {
    self.operations = operations
    self.clipboardRestoreScheduler = clipboardRestoreScheduler
    self.targetActivationWaiter = targetActivationWaiter
  }

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
      operations.isEditable(element)
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

  func deliver(_ request: DeliveryRequest) async -> DeliveryOutcome {
    AppLog.delivery.info(
      "delivery_requested strategy=\(request.strategy.rawValue, privacy: .public) target_available=\(request.target != nil, privacy: .public)"
    )
    let clipboardSnapshot =
      request.strategy == .paste && request.clipboardHandling == .restorePrevious
      ? operations.captureClipboard()
      : nil
    guard operations.copy(request.text) else { return .failed(.clipboardWriteFailed) }
    let recognizedClipboardChangeCount = operations.clipboardChangeCount()
    guard request.strategy != .clipboard else { return .clipboard }
    guard let target = request.target else { return .clipboardFallback(.targetUnavailable) }
    if let failure = targetFailure(target) { return .clipboardFallback(failure) }
    guard operations.activate(pid: target.pid) else { return .clipboardFallback(.activationFailed) }
    guard await targetActivationWaiter.waitForActivation(
      pid: target.pid,
      isActive: operations.isActive(pid:)
    ) else { return .clipboardFallback(.activationTimedOut) }
    guard Task.isCancelled == false else { return .clipboardFallback(.activationTimedOut) }
    switch request.strategy {
    case .paste:
      guard operations.postCommand(keyCode: 9) else {
        return .clipboardFallback(.pasteEventUnavailable)
      }
      if let clipboardSnapshot {
        scheduleClipboardRestore(clipboardSnapshot, expectedChangeCount: recognizedClipboardChangeCount)
      }
      let verification =
        request.verifyPaste
        ? await operations.verifyPastedText(request.text, in: target.element)
        : .notRequested
      guard Task.isCancelled == false else {
        return .pasted(request.clipboardHandling, .unavailable)
      }
      lastTarget = target
      return .pasted(request.clipboardHandling, verification)
    case .accessibility:
      guard operations.replaceSelectedText(in: target.element, with: request.text) else {
        return .clipboardFallback(.accessibilityInsertionFailed)
      }
      lastTarget = target
      return .accessibilityInserted
    case .clipboard:
      return .clipboard
    }
  }

  func undo() {
    guard let lastTarget, targetFailure(lastTarget) == nil else { return }
    _ = operations.activate(pid: lastTarget.pid)
    _ = operations.postCommand(keyCode: 6)
    AppLog.delivery.info("delivery_undo_requested")
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
      isApplicationRunning: operations.isApplicationRunning(pid: target.pid),
      isEditable: operations.isEditable(target.element)
    )
  }

  private func scheduleClipboardRestore(_ snapshot: ClipboardSnapshot, expectedChangeCount: Int) {
    let operations = self.operations
    clipboardRestoreScheduler.schedule {
      guard operations.clipboardChangeCount() == expectedChangeCount else { return }
      _ = operations.restoreClipboard(snapshot)
    }
  }
}
