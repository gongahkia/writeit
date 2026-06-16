@preconcurrency import CoreMotion
import Foundation

public enum HeadGesture: Equatable, Sendable {
    case nod
    case shake
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

@MainActor
public final class HeadGestureDetector {
    private let motionManager = CMHeadphoneMotionManager()
    private let queue = OperationQueue()
    private var latestPitch: Double?
    private var latestYaw: Double?
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

    public func start(onGesture: @escaping @MainActor @Sendable (HeadGesture) -> Void) {
        guard isAvailable, !motionManager.isDeviceMotionActive else {
            return
        }

        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let motion else {
                return
            }

            Task { @MainActor in
                self?.handle(motion: motion, onGesture: onGesture)
            }
        }
    }

    public func stop() {
        motionManager.stopDeviceMotionUpdates()
        latestPitch = nil
        latestYaw = nil
    }

    public func calibrate() -> Bool {
        guard let latestPitch, let latestYaw else {
            return false
        }

        classifier.calibrate(pitch: latestPitch, yaw: latestYaw)
        return true
    }

    private func handle(motion: CMDeviceMotion, onGesture: @MainActor @Sendable (HeadGesture) -> Void) {
        let pitch = motion.attitude.pitch
        let yaw = motion.attitude.yaw
        latestPitch = pitch
        latestYaw = yaw

        if let gesture = classifier.classify(pitch: pitch, yaw: yaw) {
            onGesture(gesture)
        }
    }
}
