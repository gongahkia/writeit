import Foundation

public struct DiagnosticBundleAppDataLocation: Codable, Equatable, Sendable {
    public let name: String
    public let path: String
    public let exists: Bool

    public init(name: String, path: String, exists: Bool) {
        self.name = name
        self.path = path
        self.exists = exists
    }
}

public struct DiagnosticBundleSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let appName: String
    public let statusLines: [String]
    public let appDataLocations: [DiagnosticBundleAppDataLocation]
    public let auditEntries: [AuditLogEntry]
    public let telemetryRecords: [LocalTelemetryRecord]

    public init(
        generatedAt: Date = Date(),
        appName: String = CerberusCore.appName,
        statusLines: [String],
        appDataLocations: [DiagnosticBundleAppDataLocation],
        auditEntries: [AuditLogEntry],
        telemetryRecords: [LocalTelemetryRecord]
    ) {
        self.generatedAt = generatedAt
        self.appName = appName
        self.statusLines = statusLines
        self.appDataLocations = appDataLocations
        self.auditEntries = auditEntries
        self.telemetryRecords = telemetryRecords
    }
}

public struct DiagnosticBundleExporter: Sendable {
    private let redactor: AdapterTrainingRedactor
    private let encoder: JSONEncoder

    public init(redactor: AdapterTrainingRedactor = .default) {
        self.redactor = redactor
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    public func redactedSnapshot(from snapshot: DiagnosticBundleSnapshot) -> DiagnosticBundleSnapshot {
        DiagnosticBundleSnapshot(
            generatedAt: snapshot.generatedAt,
            appName: snapshot.appName,
            statusLines: snapshot.statusLines.map(redactor.redact),
            appDataLocations: snapshot.appDataLocations.map { location in
                DiagnosticBundleAppDataLocation(
                    name: location.name,
                    path: redactor.redact(location.path),
                    exists: location.exists
                )
            },
            auditEntries: snapshot.auditEntries.map { entry in
                AuditLogEntry(
                    timestamp: entry.timestamp,
                    toolName: entry.toolName,
                    argumentsSummary: redactor.redact(entry.argumentsSummary),
                    resultSummary: redactor.redact(entry.resultSummary),
                    previousHash: entry.previousHash,
                    signature: nil
                )
            },
            telemetryRecords: snapshot.telemetryRecords
        )
    }

    public func write(_ snapshot: DiagnosticBundleSnapshot, to outputURL: URL) throws {
        let data = try encoder.encode(redactedSnapshot(from: snapshot))
        try data.write(to: outputURL, options: .atomic)
    }
}
