import CoreAudio
import Foundation

public struct AudioOutputDevice: Equatable, Sendable {
    public let id: UInt32
    public let name: String

    public init(id: UInt32, name: String) {
        self.id = id
        self.name = name
    }

    public var isLikelyAirPods: Bool {
        name.range(of: "airpods", options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    public var displayName: String {
        isLikelyAirPods ? "\(name) (AirPods)" : name
    }
}

public enum AudioOutputRouteError: Error, Equatable, LocalizedError, Sendable {
    case missingDefaultDevice
    case coreAudioStatus(OSStatus, operation: String)

    public var errorDescription: String? {
        switch self {
        case .missingDefaultDevice:
            "No default output device is available."
        case let .coreAudioStatus(status, operation):
            "CoreAudio \(operation) failed with status \(status)."
        }
    }
}

public enum AudioOutputRouteInspector {
    public static func defaultOutputDevice() throws -> AudioOutputDevice {
        var address = defaultOutputDeviceAddress()
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        try throwIfNeeded(status, operation: "default output lookup")
        guard deviceID != kAudioObjectUnknown else {
            throw AudioOutputRouteError.missingDefaultDevice
        }
        return AudioOutputDevice(id: UInt32(deviceID), name: try deviceName(for: deviceID))
    }

    static func defaultOutputDeviceAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func deviceName(for deviceID: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &unmanagedName)
        try throwIfNeeded(status, operation: "device name lookup")
        guard let unmanagedName else {
            throw AudioOutputRouteError.coreAudioStatus(OSStatus(paramErr), operation: "device name lookup")
        }
        return unmanagedName.takeRetainedValue() as String
    }

    fileprivate static func throwIfNeeded(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw AudioOutputRouteError.coreAudioStatus(status, operation: operation)
        }
    }
}

public final class AudioOutputRouteMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.gongahkia.cerberus.audio-output-route")
    private let listenerBlock: AudioObjectPropertyListenerBlock
    private let lock = NSLock()
    private var isStarted = false

    public init(onChange: @escaping @Sendable () -> Void) {
        listenerBlock = { count, addresses in
            for index in 0..<Int(count) {
                guard addresses[index].mSelector == kAudioHardwarePropertyDefaultOutputDevice else {
                    continue
                }
                onChange()
                return
            }
        }
    }

    deinit {
        stop()
    }

    public func start() throws {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard !isStarted else {
            return
        }
        var address = AudioOutputRouteInspector.defaultOutputDeviceAddress()
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            listenerBlock
        )
        try AudioOutputRouteInspector.throwIfNeeded(status, operation: "default output listener registration")
        isStarted = true
    }

    public func stop() {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard isStarted else {
            return
        }
        var address = AudioOutputRouteInspector.defaultOutputDeviceAddress()
        _ = AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            listenerBlock
        )
        isStarted = false
    }
}
