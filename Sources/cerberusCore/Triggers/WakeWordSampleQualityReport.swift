import Foundation

public struct WakeWordSampleQualityReport: Equatable, Sendable {
    public let classCounts: [String: Int]
    public let manifestRecordCount: Int
    public let missingManifestRecordCount: Int
    public let shortSampleCount: Int
    public let longSampleCount: Int
    public let averageDurationSeconds: Double?
    public let warnings: [String]

    public init(
        classCounts: [String: Int],
        manifestRecordCount: Int,
        missingManifestRecordCount: Int,
        shortSampleCount: Int,
        longSampleCount: Int,
        averageDurationSeconds: Double?,
        warnings: [String]
    ) {
        self.classCounts = classCounts
        self.manifestRecordCount = manifestRecordCount
        self.missingManifestRecordCount = missingManifestRecordCount
        self.shortSampleCount = shortSampleCount
        self.longSampleCount = longSampleCount
        self.averageDurationSeconds = averageDurationSeconds
        self.warnings = warnings
    }
}

public enum WakeWordSampleQualityReporter {
    public static func report(
        in baseDirectoryURL: URL,
        targetLabel: String,
        minimumSamplesPerClass: Int = 20,
        shortDurationThreshold: Double = 0.5,
        longDurationThreshold: Double = 5.0
    ) throws -> WakeWordSampleQualityReport {
        let classCounts = try WakeWordSampleDataset.classCounts(in: baseDirectoryURL)
        let records = try WakeWordSampleDataset.manifestRecords(in: baseDirectoryURL)
        let audioFileCount = classCounts.values.reduce(0, +)
        let durations = records.map(\.durationSeconds)
        let averageDuration = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        var warnings: [String] = []

        if classCounts.count < 2 {
            warnings.append("needs at least two labeled classes")
        }
        if classCounts[targetLabel] == nil {
            warnings.append("target label \(targetLabel) is missing")
        }
        for (label, count) in classCounts.sorted(by: { $0.key < $1.key }) where count < minimumSamplesPerClass {
            warnings.append("\(label) has only \(count) sample(s)")
        }

        let missingManifestRecordCount = max(0, audioFileCount - records.count)
        if missingManifestRecordCount > 0 {
            warnings.append("\(missingManifestRecordCount) audio file(s) lack manifest metadata")
        }

        let shortSampleCount = durations.filter { $0 < shortDurationThreshold }.count
        if shortSampleCount > 0 {
            warnings.append("\(shortSampleCount) sample(s) are shorter than \(shortDurationThreshold)s")
        }

        let longSampleCount = durations.filter { $0 > longDurationThreshold }.count
        if longSampleCount > 0 {
            warnings.append("\(longSampleCount) sample(s) are longer than \(longDurationThreshold)s")
        }

        return WakeWordSampleQualityReport(
            classCounts: classCounts,
            manifestRecordCount: records.count,
            missingManifestRecordCount: missingManifestRecordCount,
            shortSampleCount: shortSampleCount,
            longSampleCount: longSampleCount,
            averageDurationSeconds: averageDuration,
            warnings: warnings
        )
    }

    public static func render(_ report: WakeWordSampleQualityReport) -> String {
        let classes = report.classCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        let average = report.averageDurationSeconds.map { String(format: "%.2fs", $0) } ?? "unavailable"
        let warningLines = report.warnings.isEmpty
            ? "warnings: none"
            : "warnings:\n" + report.warnings.map { "- \($0)" }.joined(separator: "\n")

        return """
        sample quality:
        classes: \(classes.isEmpty ? "none" : classes)
        manifest records: \(report.manifestRecordCount)
        missing manifest records: \(report.missingManifestRecordCount)
        short samples: \(report.shortSampleCount)
        long samples: \(report.longSampleCount)
        average duration: \(average)
        \(warningLines)
        """
    }
}
