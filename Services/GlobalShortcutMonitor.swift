import ApplicationServices
import Foundation

enum ShortcutEvent: Equatable {
  case down
  case up
}

enum EventTapDisablement: Equatable {
  case timeout
  case userInput

  init?(type: CGEventType) {
    switch type {
    case .tapDisabledByTimeout: self = .timeout
    case .tapDisabledByUserInput: self = .userInput
    default: return nil
    }
  }

  var logValue: String {
    switch self {
    case .timeout: "timeout"
    case .userInput: "user_input"
    }
  }
}

final class GlobalShortcutMonitor: GlobalShortcutMonitoring {
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var shortcut = Shortcut.default
  private var handler: ((CaptureCommand) -> Void)?

  func start(shortcut: Shortcut, handler: @escaping (CaptureCommand) -> Void) {
    stop()
    self.shortcut = shortcut
    self.handler = handler
    let events = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
    let context = Unmanaged.passUnretained(self).toOpaque()
    eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .listenOnly,
      eventsOfInterest: CGEventMask(events),
      callback: { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.handle(type: type, event: event)
        return Unmanaged.passUnretained(event)
      },
      userInfo: context
    )
    guard let eventTap else {
      AppLog.shortcut.error("event_tap_creation_failed")
      return
    }
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    if let runLoopSource { CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
    CGEvent.tapEnable(tap: eventTap, enable: true)
    AppLog.shortcut.info("event_tap_started")
  }

  func stop() {
    if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
    eventTap = nil
    runLoopSource = nil
    AppLog.shortcut.info("event_tap_stopped")
  }

  private func handle(type: CGEventType, event: CGEvent) {
    if let disablement = EventTapDisablement(type: type) {
      reenableEventTap(after: disablement)
      return
    }
    guard type == .keyDown || type == .keyUp else { return }
    let command = CaptureKeyboardCommandResolver.resolve(
      keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
      modifiers: event.flags.rawValue,
      isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
      shortcut: shortcut,
      event: type == .keyDown ? .down : .up
    )
    if let command { handler?(command) }
  }

  private func reenableEventTap(after disablement: EventTapDisablement) {
    guard let eventTap else {
      AppLog.shortcut.error("event_tap_reenable_failed reason=\(disablement.logValue, privacy: .public)")
      return
    }
    CGEvent.tapEnable(tap: eventTap, enable: true)
    AppLog.shortcut.info("event_tap_reenabled reason=\(disablement.logValue, privacy: .public)")
  }
}
