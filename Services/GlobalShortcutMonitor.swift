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

enum EventTapLifecycleEvent: Equatable {
  case creationFailed
  case runLoopSourceCreationFailed
  case started
  case stopped
  case disabled(EventTapDisablement)
  case reenabled(EventTapDisablement)
  case reenableFailed(EventTapDisablement)

  var message: String {
    switch self {
    case .creationFailed: "event_tap_lifecycle event=creation_failed"
    case .runLoopSourceCreationFailed: "event_tap_lifecycle event=run_loop_source_creation_failed"
    case .started: "event_tap_lifecycle event=started"
    case .stopped: "event_tap_lifecycle event=stopped"
    case .disabled(let reason): "event_tap_lifecycle event=disabled reason=\(reason.logValue)"
    case .reenabled(let reason): "event_tap_lifecycle event=reenabled reason=\(reason.logValue)"
    case .reenableFailed(let reason):
      "event_tap_lifecycle event=reenable_failed reason=\(reason.logValue)"
    }
  }

  var isError: Bool {
    switch self {
    case .creationFailed, .runLoopSourceCreationFailed, .reenableFailed: true
    case .started, .stopped, .disabled, .reenabled: false
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
      log(.creationFailed)
      return
    }
    guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
      self.eventTap = nil
      log(.runLoopSourceCreationFailed)
      return
    }
    self.runLoopSource = runLoopSource
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    log(.started)
  }

  func stop() {
    let wasActive = eventTap != nil || runLoopSource != nil
    if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
    eventTap = nil
    runLoopSource = nil
    if wasActive { log(.stopped) }
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
    log(.disabled(disablement))
    guard let eventTap else {
      log(.reenableFailed(disablement))
      return
    }
    CGEvent.tapEnable(tap: eventTap, enable: true)
    log(CGEvent.tapIsEnabled(tap: eventTap) ? .reenabled(disablement) : .reenableFailed(disablement))
  }

  private func log(_ event: EventTapLifecycleEvent) {
    if event.isError {
      AppLog.shortcut.error("\(event.message, privacy: .public)")
    } else {
      AppLog.shortcut.info("\(event.message, privacy: .public)")
    }
  }
}
