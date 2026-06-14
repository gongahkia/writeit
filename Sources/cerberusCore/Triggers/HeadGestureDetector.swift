@preconcurrency import CoreMotion
import Foundation

public enum HeadGesture: Equatable, Sendable {
    case nod
    case shake
}

@MainActor
public final class HeadGestureDetector {
    private let motionManager = CMHeadphoneMotionManager()
    private let queue = OperationQueue()
    private var lastPitch: Double?
    private var lastYaw: Double?
    private var lastTriggerDate = Date.distantPast

    private let pitchThreshold: Double
    private let yawThreshold: Double
    private let cooldown: TimeInterval

    public init(pitchThreshold: Double = 0.35, yawThreshold: Double = 0.45, cooldown: TimeInterval = 1.2) {
        self.pitchThreshold = pitchThreshold
        self.yawThreshold = yawThreshold
        self.cooldown = cooldown
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
        lastPitch = nil
        lastYaw = nil
    }

    private func handle(motion: CMDeviceMotion, onGesture: @MainActor @Sendable (HeadGesture) -> Void) {
        let pitch = motion.attitude.pitch
        let yaw = motion.attitude.yaw
        defer {
            lastPitch = pitch
            lastYaw = yaw
        }

        guard Date().timeIntervalSince(lastTriggerDate) >= cooldown else {
            return
        }

        if let lastPitch, abs(pitch - lastPitch) >= pitchThreshold {
            lastTriggerDate = Date()
            onGesture(.nod)
            return
        }

        if let lastYaw, abs(yaw - lastYaw) >= yawThreshold {
            lastTriggerDate = Date()
            onGesture(.shake)
        }
    }
}
