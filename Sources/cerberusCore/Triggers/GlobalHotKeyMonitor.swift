import AppKit
import Foundation

public struct HotKeyModifiers: Codable, Equatable, Sendable {
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

public struct HotKeyConfiguration: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let keyCode: UInt16
    public let modifiers: HotKeyModifiers

    public init(id: String, displayName: String, keyCode: UInt16, modifiers: HotKeyModifiers) {
        self.id = id
        self.displayName = displayName
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let controlOptionSpace = HotKeyConfiguration(
        id: "control-option-space",
        displayName: "Control Option Space",
        keyCode: 49,
        modifiers: HotKeyModifiers(control: true, option: true)
    )
    public static let controlShiftSpace = HotKeyConfiguration(
        id: "control-shift-space",
        displayName: "Control Shift Space",
        keyCode: 49,
        modifiers: HotKeyModifiers(control: true, shift: true)
    )
    public static let commandOptionSpace = HotKeyConfiguration(
        id: "command-option-space",
        displayName: "Command Option Space",
        keyCode: 49,
        modifiers: HotKeyModifiers(option: true, command: true)
    )
    public static let presets = [
        controlOptionSpace,
        controlShiftSpace,
        commandOptionSpace
    ]

    public static func preset(id: String) -> HotKeyConfiguration {
        presets.first { $0.id == id } ?? controlOptionSpace
    }
}

@MainActor
public final class GlobalHotKeyMonitor {
    private var configuration: HotKeyConfiguration
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onTrigger: (@MainActor @Sendable () -> Void)?

    public init(configuration: HotKeyConfiguration = .controlOptionSpace) {
        self.configuration = configuration
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

    public func update(configuration: HotKeyConfiguration) {
        let trigger = onTrigger
        let wasRunning = isRunning
        stop()
        self.configuration = configuration
        if wasRunning, let trigger {
            start(onTrigger: trigger)
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
        guard keyCode == configuration.keyCode, modifiers == configuration.modifiers else {
            return
        }
        onTrigger?()
    }
}
