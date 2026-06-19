import Foundation

public struct AdapterFailureCircuitBreaker: Equatable, Sendable {
    public let threshold: Int
    public private(set) var consecutiveFailures: Int

    public init(threshold: Int = 3, consecutiveFailures: Int = 0) {
        self.threshold = max(1, threshold)
        self.consecutiveFailures = max(0, consecutiveFailures)
    }

    public mutating func recordSuccess() {
        consecutiveFailures = 0
    }

    public mutating func recordFailure(modelProfile: String) -> Bool {
        guard modelProfile != "default" else {
            consecutiveFailures = 0
            return false
        }

        consecutiveFailures += 1
        return consecutiveFailures >= threshold
    }

    public mutating func reset() {
        consecutiveFailures = 0
    }
}
