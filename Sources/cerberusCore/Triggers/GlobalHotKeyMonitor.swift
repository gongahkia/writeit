import AppKit
import Foundation

public struct HotKeyModifiers: Equatable, Sendable {
    public let control: Bool
    public let option: Bool
    public let command: Bool
    public let shift: Bool

    public init(control: Bool = false, option: Bool = false, command: Bool = false, shift: Bool = false) {
        self.control = control
        self.option = option
        self.command = command
        self.shift = shift
    }

    init(_ flags: NSEvent.ModifierFlags) {
        control = flags.contains(.control)
        option = flags.contains(.option)
        command = flags.contains(.command)
        shift = flags.contains(.shift)
    }
}

@MainActor
public final class GlobalHotKeyMonitor {
    private let keyCode: UInt16
    private let modifiers: HotKeyModifiers
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onTrigger: (@MainActor @Sendable () -> Void)?

    public init(keyCode: UInt16 = 49, modifiers: HotKeyModifiers = HotKeyModifiers(control: true, option: true)) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var isRunning: Bool {
        globalMonitor != nil || localMonitor != nil
    }

    public func start(onTrigger: @escaping @MainActor @Sendable () -> Void) {
        guard !isRunning else {
            return
        }

        self.onTrigger = onTrigger
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = UInt16(event.keyCode)
            let modifiers = HotKeyModifiers(event.modifierFlags)
            Task { @MainActor in
                self?.handle(keyCode: keyCode, modifiers: modifiers)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = UInt16(event.keyCode)
            let modifiers = HotKeyModifiers(event.modifierFlags)
            Task { @MainActor in
                self?.handle(keyCode: keyCode, modifiers: modifiers)
            }
            return event
        }
    }

    public func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }

        globalMonitor = nil
        localMonitor = nil
        onTrigger = nil
    }

    private func handle(keyCode: UInt16, modifiers: HotKeyModifiers) {
        guard keyCode == self.keyCode, modifiers == self.modifiers else {
            return
        }
        onTrigger?()
    }
}
