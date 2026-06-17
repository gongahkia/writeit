@preconcurrency import CoreMotion
import Foundation

public enum HeadGesture: Equatable, Sendable {
    case nod
    case shake
}

public struct HeadGestureMotionSnapshot: Equatable, Sendable {
    public let timestamp: Date
    public let pitch: Double
    public let yaw: Double
    public let neutralPitch: Double?
    public let neutralYaw: Double?
    public let deltaPitch: Double?
    public let deltaYaw: Double?
    public let pitchThreshold: Double
    public let yawThreshold: Double
    public let gesture: HeadGesture?

    public init(
        timestamp: Date = Date(),
        pitch: Double,
        yaw: Double,
        neutralPitch: Double? = nil,
        neutralYaw: Double? = nil,
        deltaPitch: Double? = nil,
        deltaYaw: Double? = nil,
        pitchThreshold: Double,
        yawThreshold: Double,
        gesture: HeadGesture? = nil
    ) {
        self.timestamp = timestamp
        self.pitch = pitch
        self.yaw = yaw
        self.neutralPitch = neutralPitch
        self.neutralYaw = neutralYaw
        self.deltaPitch = deltaPitch
        self.deltaYaw = deltaYaw
        self.pitchThreshold = pitchThreshold
        self.yawThreshold = yawThreshold
        self.gesture = gesture
    }

    public static let csvHeader = "timestamp,pitch,yaw,neutralPitch,neutralYaw,deltaPitch,deltaYaw,pitchThreshold,yawThreshold,gesture"

    public var csvLine: String {
        [
            ISO8601DateFormatter().string(from: timestamp),
            Self.format(pitch),
            Self.format(yaw),
            neutralPitch.map(Self.format) ?? "",
            neutralYaw.map(Self.format) ?? "",
            deltaPitch.map(Self.format) ?? "",
            deltaYaw.map(Self.format) ?? "",
            Self.format(pitchThreshold),
            Self.format(yawThreshold),
            gesture.map(String.init(describing:)) ?? ""
        ].joined(separator: ",")
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}

public actor HeadGestureValidationLog {
    private let fileURL: URL

    public init(fileURL: URL = HeadGestureValidationLog.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func append(_ snapshot: HeadGestureMotionSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let line = Data(snapshot.csvLine.utf8)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n".utf8))
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            var data = Data((HeadGestureMotionSnapshot.csvHeader + "\n").utf8)
            data.append(line)
            try data.write(to: fileURL, options: .atomic)
        }
    }

    public static func defaultFileURL() -> URL {
        CerberusDirectories.applicationSupportFile("head-gesture-validation.csv")
    }
}

public struct HeadGestureClassifier: Sendable {
    public var pitchThreshold: Double
    public var yawThreshold: Double
    public var cooldown: TimeInterval
    private var neutralPitch: Double?
    private var neutralYaw: Double?
    private var lastTriggerDate = Date.distantPast

    public init(pitchThreshold: Double = 0.35, yawThreshold: Double = 0.45, cooldown: TimeInterval = 1.2) {
        self.pitchThreshold = pitchThreshold
        self.yawThreshold = yawThreshold
        self.cooldown = cooldown
    }

    public mutating func calibrate(pitch: Double, yaw: Double) {
        neutralPitch = pitch
        neutralYaw = yaw
    }

    public mutating func updateThresholds(pitch: Double, yaw: Double, cooldown: TimeInterval? = nil) {
        pitchThreshold = pitch
        yawThreshold = yaw
        if let cooldown {
            self.cooldown = cooldown
        }
    }

    public func deltas(pitch: Double, yaw: Double) -> HeadGestureDeltas {
        let neutralPitch = neutralPitch ?? pitch
        let neutralYaw = neutralYaw ?? yaw
        return HeadGestureDeltas(
            neutralPitch: neutralPitch,
            neutralYaw: neutralYaw,
            deltaPitch: pitch - neutralPitch,
            deltaYaw: yaw - neutralYaw
        )
    }

    public mutating func classify(pitch: Double, yaw: Double, at date: Date = Date()) -> HeadGesture? {
        guard let neutralPitch, let neutralYaw else {
            calibrate(pitch: pitch, yaw: yaw)
            return nil
        }

        guard date.timeIntervalSince(lastTriggerDate) >= cooldown else {
            return nil
        }

        if abs(pitch - neutralPitch) >= pitchThreshold {
            lastTriggerDate = date
            calibrate(pitch: pitch, yaw: yaw)
            return .nod
        }

        if abs(yaw - neutralYaw) >= yawThreshold {
            lastTriggerDate = date
            calibrate(pitch: pitch, yaw: yaw)
            return .shake
        }

        return nil
    }
}

public struct HeadGestureDeltas: Equatable, Sendable {
    public let neutralPitch: Double
    public let neutralYaw: Double
    public let deltaPitch: Double
    public let deltaYaw: Double
}

@MainActor
public final class HeadGestureDetector {
    private let motionManager = CMHeadphoneMotionManager()
    private let queue = OperationQueue()
    private var latestPitch: Double?
    private var latestYaw: Double?
    private var lastSampleDate = Date.distantPast
    private var classifier: HeadGestureClassifier

    public init(pitchThreshold: Double = 0.35, yawThreshold: Double = 0.45, cooldown: TimeInterval = 1.2) {
        classifier = HeadGestureClassifier(
            pitchThreshold: pitchThreshold,
            yawThreshold: yawThreshold,
            cooldown: cooldown
        )
        queue.name = "dev.gongahkia.cerberus.head-motion"
        queue.qualityOfService = .userInteractive
    }

    public var isAvailable: Bool {
        motionManager.isDeviceMotionAvailable
    }

    public func start(
        onGesture: @escaping @MainActor @Sendable (HeadGesture) -> Void,
        onSample: (@MainActor @Sendable (HeadGestureMotionSnapshot) -> Void)? = nil
    ) {
        guard isAvailable, !motionManager.isDeviceMotionActive else {
            return
        }

        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let motion else {
                return
            }

            Task { @MainActor in
                self?.handle(motion: motion, onGesture: onGesture, onSample: onSample)
            }
        }
    }

    public func stop() {
        motionManager.stopDeviceMotionUpdates()
        latestPitch = nil
        latestYaw = nil
        lastSampleDate = .distantPast
    }

    public func calibrate() -> Bool {
        guard let latestPitch, let latestYaw else {
            return false
        }

        classifier.calibrate(pitch: latestPitch, yaw: latestYaw)
        return true
    }

    public func updateThresholds(pitch: Double, yaw: Double) {
        classifier.updateThresholds(pitch: pitch, yaw: yaw)
    }

    private func handle(
        motion: CMDeviceMotion,
        onGesture: @MainActor @Sendable (HeadGesture) -> Void,
        onSample: (@MainActor @Sendable (HeadGestureMotionSnapshot) -> Void)?
    ) {
        let pitch = motion.attitude.pitch
        let yaw = motion.attitude.yaw
        let now = Date()
        latestPitch = pitch
        latestYaw = yaw

        let deltas = classifier.deltas(pitch: pitch, yaw: yaw)
        let gesture = classifier.classify(pitch: pitch, yaw: yaw, at: now)
        if gesture != nil || now.timeIntervalSince(lastSampleDate) >= 0.1 {
            lastSampleDate = now
            onSample?(HeadGestureMotionSnapshot(
                timestamp: now,
                pitch: pitch,
                yaw: yaw,
                neutralPitch: deltas.neutralPitch,
                neutralYaw: deltas.neutralYaw,
                deltaPitch: deltas.deltaPitch,
                deltaYaw: deltas.deltaYaw,
                pitchThreshold: classifier.pitchThreshold,
                yawThreshold: classifier.yawThreshold,
                gesture: gesture
            ))
        }

        if let gesture {
            onGesture(gesture)
        }
    }
}
