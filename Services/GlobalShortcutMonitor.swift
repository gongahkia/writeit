import ApplicationServices
import Foundation

enum ShortcutEvent {
  case down
  case up
}

final class GlobalShortcutMonitor {
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var shortcut = Shortcut.default
  private var handler: ((ShortcutEvent) -> Void)?

  func start(shortcut: Shortcut, handler: @escaping (ShortcutEvent) -> Void) {
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
    guard let eventTap else { return }
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    if let runLoopSource { CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
    CGEvent.tapEnable(tap: eventTap, enable: true)
  }

  func stop() {
    if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
    eventTap = nil
    runLoopSource = nil
  }

  private func handle(type: CGEventType, event: CGEvent) {
    guard type == .keyDown || type == .keyUp else { return }
    guard UInt16(event.getIntegerValueField(.keyboardEventKeycode)) == shortcut.keyCode else { return }
    let relevant = CGEventFlags.maskCommand.union(.maskShift).union(.maskAlternate).union(.maskControl)
    guard event.flags.intersection(relevant).rawValue == shortcut.modifiers else { return }
    if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
    handler?(type == .keyDown ? .down : .up)
  }
}
