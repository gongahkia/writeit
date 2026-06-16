import Foundation

public struct LatencyBenchmarkSummary: Equatable, Sendable {
    public let count: Int
    public let minimum: Double
    public let median: Double
    public let p95: Double
    public let maximum: Double
    public let average: Double

    public init(samples: [Double]) {
        let sorted = samples.sorted()
        count = sorted.count
        minimum = sorted.first ?? 0
        median = Self.percentile(sorted, 0.5)
        p95 = Self.percentile(sorted, 0.95)
        maximum = sorted.last ?? 0
        average = sorted.isEmpty ? 0 : sorted.reduce(0, +) / Double(sorted.count)
    }

    private static func percentile(_ sorted: [Double], _ percentile: Double) -> Double {
        guard !sorted.isEmpty else {
            return 0
        }
        guard sorted.count > 1 else {
            return sorted[0]
        }
        let clamped = max(0, min(1, percentile))
        let position = clamped * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        guard lower != upper else {
            return sorted[lower]
        }
        let weight = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * weight
    }

    public func line(label: String) -> String {
        String(
            format: "%@: count=%d min=%.3fs median=%.3fs p95=%.3fs max=%.3fs avg=%.3fs",
            label,
            count,
            minimum,
            median,
            p95,
            maximum,
            average
        )
    }
}
