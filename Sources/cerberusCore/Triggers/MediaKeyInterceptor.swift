import AppKit
import CoreGraphics
import Foundation

public enum MediaKeyTrigger: Equatable, Sendable {
    case singlePress
    case triplePress
}

@MainActor
public final class MediaKeyInterceptor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var recentPressDates: [Date] = []
    private let triplePressWindow: TimeInterval

    public init(triplePressWindow: TimeInterval = 0.8) {
        self.triplePressWindow = triplePressWindow
    }

    public func start(onTrigger: @escaping @MainActor @Sendable (MediaKeyTrigger) -> Void) -> Bool {
        guard eventTap == nil else {
            return true
        }

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let eventMask = CGEventMask(1 << 14)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: Self.eventCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        eventTap = tap
        runLoopSource = source
        triggerHandler = onTrigger

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        triggerHandler = nil
        recentPressDates = []
    }

    private var triggerHandler: (@MainActor @Sendable (MediaKeyTrigger) -> Void)?

    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard type.rawValue == 14, let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
        Task { @MainActor in
            interceptor.handle(event: event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handle(event: CGEvent) {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8,
              isKeyDown(nsEvent) else {
            return
        }

        let now = Date()
        recentPressDates.append(now)
        recentPressDates = recentPressDates.filter { now.timeIntervalSince($0) <= triplePressWindow }

        if recentPressDates.count >= 3 {
            recentPressDates = []
            triggerHandler?(.triplePress)
        } else {
            triggerHandler?(.singlePress)
        }
    }

    private func isKeyDown(_ event: NSEvent) -> Bool {
        let keyFlags = event.data1 & 0x0000ffff
        let keyState = (keyFlags & 0xff00) >> 8
        return keyState == 0x0a
    }
}
