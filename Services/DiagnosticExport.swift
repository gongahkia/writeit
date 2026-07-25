import Foundation

enum DiagnosticExportError: LocalizedError, Equatable {
  case unwritableFile

  var errorDescription: String? {
    switch self {
    case .unwritableFile: "Diagnostic export could not be saved."
    }
  }
}

struct DiagnosticExportEvent: Codable, Equatable, Sendable {
  let occurredAt: Date
  let kind: DiagnosticEventKind

  init(event: DiagnosticEvent) {
    occurredAt = event.occurredAt
    kind = event.kind
  }

  private enum CodingKeys: String, CodingKey {
    case occurredAt = "occurred_at"
    case kind
  }
}

struct DiagnosticExportArchive: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let generatedAt: Date
  let events: [DiagnosticExportEvent]

  init(events: [DiagnosticEvent], generatedAt: Date = Date()) {
    schemaVersion = Self.currentSchemaVersion
    self.generatedAt = generatedAt
    self.events = events.map(DiagnosticExportEvent.init)
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case generatedAt = "generated_at"
    case events
  }
}

enum DiagnosticExportCodec {
  static func encode(_ archive: DiagnosticExportArchive) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(archive)
  }
}

enum DiagnosticExportFileStore {
  static func write(_ data: Data, to url: URL) throws {
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      throw DiagnosticExportError.unwritableFile
    }
  }
}
