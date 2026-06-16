import Foundation

public struct HeadGestureValidationSample: Equatable, Sendable {
    public let timestamp: Date?
    public let pitch: Double
    public let yaw: Double
    public let neutralPitch: Double?
    public let neutralYaw: Double?
    public let deltaPitch: Double
    public let deltaYaw: Double
    public let pitchThreshold: Double
    public let yawThreshold: Double
    public let gesture: HeadGesture?

    public var absDeltaPitch: Double {
        abs(deltaPitch)
    }

    public var absDeltaYaw: Double {
        abs(deltaYaw)
    }
}

public struct HeadGestureValidationReport: Equatable, Sendable {
    public let sampleCount: Int
    public let quietSampleCount: Int
    public let nodCount: Int
    public let shakeCount: Int
    public let maxQuietPitchDelta: Double
    public let maxQuietYawDelta: Double
    public let minNodPitchDelta: Double?
    public let minShakeYawDelta: Double?
    public let suggestedPitchThreshold: Double?
    public let suggestedYawThreshold: Double?

    public var hasSamples: Bool {
        sampleCount > 0
    }
}

public enum HeadGestureValidationAnalysisError: Error, LocalizedError, Equatable {
    case emptyCSV
    case missingColumn(String)
    case malformedRow(Int)
    case invalidNumber(row: Int, column: String, value: String)

    public var errorDescription: String? {
        switch self {
        case .emptyCSV:
            "Head gesture CSV is empty."
        case let .missingColumn(column):
            "Head gesture CSV is missing column: \(column)."
        case let .malformedRow(row):
            "Head gesture CSV row \(row) has the wrong number of columns."
        case let .invalidNumber(row, column, value):
            "Head gesture CSV row \(row) has invalid \(column): \(value)."
        }
    }
}

public enum HeadGestureValidationAnalyzer {
    public static func parseCSV(_ text: String) throws -> [HeadGestureValidationSample] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let headerLine = lines.first else {
            throw HeadGestureValidationAnalysisError.emptyCSV
        }

        let headers = split(headerLine)
        let index = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($0.element, $0.offset) })
        for column in ["timestamp", "pitch", "yaw", "pitchThreshold", "yawThreshold", "gesture"] {
            guard index[column] != nil else {
                throw HeadGestureValidationAnalysisError.missingColumn(column)
            }
        }

        return try lines.dropFirst().enumerated().map { offset, line in
            let rowNumber = offset + 2
            let fields = split(line)
            guard fields.count == headers.count else {
                throw HeadGestureValidationAnalysisError.malformedRow(rowNumber)
            }

            let pitch = try double(fields, index, "pitch", rowNumber)
            let yaw = try double(fields, index, "yaw", rowNumber)
            let neutralPitch = try optionalDouble(fields, index, "neutralPitch", rowNumber)
            let neutralYaw = try optionalDouble(fields, index, "neutralYaw", rowNumber)
            let deltaPitch = try optionalDouble(fields, index, "deltaPitch", rowNumber)
                ?? neutralPitch.map { pitch - $0 }
                ?? pitch
            let deltaYaw = try optionalDouble(fields, index, "deltaYaw", rowNumber)
                ?? neutralYaw.map { yaw - $0 }
                ?? yaw

            return HeadGestureValidationSample(
                timestamp: ISO8601DateFormatter().date(from: fields[index["timestamp"] ?? 0]),
                pitch: pitch,
                yaw: yaw,
                neutralPitch: neutralPitch,
                neutralYaw: neutralYaw,
                deltaPitch: deltaPitch,
                deltaYaw: deltaYaw,
                pitchThreshold: try double(fields, index, "pitchThreshold", rowNumber),
                yawThreshold: try double(fields, index, "yawThreshold", rowNumber),
                gesture: gesture(from: fields[index["gesture"] ?? 0])
            )
        }
    }

    public static func report(samples: [HeadGestureValidationSample]) -> HeadGestureValidationReport {
        let quietSamples = samples.filter { $0.gesture == nil }
        let nodSamples = samples.filter { $0.gesture == .nod }
        let shakeSamples = samples.filter { $0.gesture == .shake }
        let maxQuietPitch = quietSamples.map(\.absDeltaPitch).max() ?? 0
        let maxQuietYaw = quietSamples.map(\.absDeltaYaw).max() ?? 0
        let minNodPitch = nodSamples.map(\.absDeltaPitch).min()
        let minShakeYaw = shakeSamples.map(\.absDeltaYaw).min()

        return HeadGestureValidationReport(
            sampleCount: samples.count,
            quietSampleCount: quietSamples.count,
            nodCount: nodSamples.count,
            shakeCount: shakeSamples.count,
            maxQuietPitchDelta: maxQuietPitch,
            maxQuietYawDelta: maxQuietYaw,
            minNodPitchDelta: minNodPitch,
            minShakeYawDelta: minShakeYaw,
            suggestedPitchThreshold: suggestedThreshold(noiseFloor: maxQuietPitch, signalFloor: minNodPitch),
            suggestedYawThreshold: suggestedThreshold(noiseFloor: maxQuietYaw, signalFloor: minShakeYaw)
        )
    }

    public static func render(_ report: HeadGestureValidationReport) -> String {
        guard report.hasSamples else {
            return "No head gesture samples found."
        }

        return [
            "samples: \(report.sampleCount)",
            "quiet samples: \(report.quietSampleCount)",
            "nod detections: \(report.nodCount)",
            "shake detections: \(report.shakeCount)",
            "max quiet pitch delta: \(format(report.maxQuietPitchDelta))",
            "max quiet yaw delta: \(format(report.maxQuietYawDelta))",
            "min nod pitch delta: \(report.minNodPitchDelta.map(format) ?? "n/a")",
            "min shake yaw delta: \(report.minShakeYawDelta.map(format) ?? "n/a")",
            "suggested pitch threshold: \(report.suggestedPitchThreshold.map(format) ?? "n/a")",
            "suggested yaw threshold: \(report.suggestedYawThreshold.map(format) ?? "n/a")"
        ].joined(separator: "\n")
    }

    private static func split(_ line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }

    private static func double(
        _ fields: [String],
        _ index: [String: Int],
        _ column: String,
        _ rowNumber: Int
    ) throws -> Double {
        guard let columnIndex = index[column] else {
            throw HeadGestureValidationAnalysisError.missingColumn(column)
        }
        guard let value = Double(fields[columnIndex]) else {
            throw HeadGestureValidationAnalysisError.invalidNumber(row: rowNumber, column: column, value: fields[columnIndex])
        }
        return value
    }

    private static func optionalDouble(
        _ fields: [String],
        _ index: [String: Int],
        _ column: String,
        _ rowNumber: Int
    ) throws -> Double? {
        guard let columnIndex = index[column] else {
            return nil
        }
        let rawValue = fields[columnIndex]
        guard !rawValue.isEmpty else {
            return nil
        }
        guard let value = Double(rawValue) else {
            throw HeadGestureValidationAnalysisError.invalidNumber(row: rowNumber, column: column, value: rawValue)
        }
        return value
    }

    private static func gesture(from value: String) -> HeadGesture? {
        switch value {
        case "nod":
            .nod
        case "shake":
            .shake
        default:
            nil
        }
    }

    private static func suggestedThreshold(noiseFloor: Double, signalFloor: Double?) -> Double? {
        guard noiseFloor > 0 || signalFloor != nil else {
            return nil
        }
        let noiseBased = max(0.15, noiseFloor * 1.25)
        guard let signalFloor else {
            return noiseBased
        }
        if noiseBased >= signalFloor {
            return (noiseFloor + signalFloor) / 2
        }
        return min(noiseBased, signalFloor * 0.9)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
