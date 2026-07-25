import Combine
import Foundation

enum DiagnosticEventKind: String, Codable, CaseIterable, Sendable {
  case runtimeStarted
  case runtimeStopped
}

struct DiagnosticEvent: Codable, Equatable, Identifiable, Sendable {
  static let currentSchemaVersion = 1

  let id: UUID
  let schemaVersion: Int
  let occurredAt: Date
  let kind: DiagnosticEventKind

  init(id: UUID = UUID(), occurredAt: Date, kind: DiagnosticEventKind) {
    self.id = id
    schemaVersion = Self.currentSchemaVersion
    self.occurredAt = occurredAt
    self.kind = kind
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case schemaVersion = "schema_version"
    case occurredAt = "occurred_at"
    case kind
  }
}

struct DiagnosticEventRetentionPolicy: Equatable, Sendable {
  static let `default` = Self(maximumAge: 7 * 24 * 60 * 60, maximumEvents: 200)

  let maximumAge: TimeInterval
  let maximumEvents: Int

  init(maximumAge: TimeInterval, maximumEvents: Int) {
    precondition(maximumAge > 0)
    precondition(maximumEvents > 0)
    self.maximumAge = maximumAge
    self.maximumEvents = maximumEvents
  }

  func retained(_ events: [DiagnosticEvent], at date: Date) -> [DiagnosticEvent] {
    Array(
      events
        .filter { $0.occurredAt >= date.addingTimeInterval(-maximumAge) }
        .sorted { $0.occurredAt < $1.occurredAt }
        .suffix(maximumEvents)
    )
  }
}

enum DiagnosticEventStoreError: LocalizedError, Equatable {
  case invalidArchive
  case persistenceFailed

  var errorDescription: String? {
    switch self {
    case .invalidArchive: "Saved diagnostic events could not be read."
    case .persistenceFailed: "WriteIt could not save diagnostic events."
    }
  }
}

@MainActor
final class DiagnosticEventStore: ObservableObject {
  @Published private(set) var events: [DiagnosticEvent]
  @Published private(set) var error: AppErrorPresentation?

  private let fileURL: URL
  private let retentionPolicy: DiagnosticEventRetentionPolicy
  private let now: () -> Date

  init(
    directory: URL = DiagnosticLogStore.defaultDirectory,
    retentionPolicy: DiagnosticEventRetentionPolicy = .default,
    now: @escaping () -> Date = Date.init
  ) {
    fileURL = directory.appendingPathComponent("events.json")
    self.retentionPolicy = retentionPolicy
    self.now = now
    events = []
    error = nil
    do {
      let loaded = try Self.load(from: fileURL)
      let retained = retentionPolicy.retained(loaded, at: now())
      events = retained
      if retained != loaded { try persist(retained) }
    } catch {
      self.error = .persistence(error)
    }
  }

  func record(_ kind: DiagnosticEventKind, at occurredAt: Date? = nil) {
    let updated = retentionPolicy.retained(
      events + [DiagnosticEvent(occurredAt: occurredAt ?? now(), kind: kind)], at: now())
    do {
      try persist(updated)
      events = updated
      error = nil
    } catch {
      self.error = .persistence(error)
    }
  }

  func clearError() { error = nil }

  private func persist(_ events: [DiagnosticEvent]) throws {
    let archive = DiagnosticEventArchive(events: events)
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(archive).write(to: fileURL, options: .atomic)
    } catch {
      throw DiagnosticEventStoreError.persistenceFailed
    }
  }

  private static func load(from fileURL: URL) throws -> [DiagnosticEvent] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    do {
      let archive = try JSONDecoder().decode(DiagnosticEventArchive.self, from: Data(contentsOf: fileURL))
      guard archive.schemaVersion == DiagnosticEventArchive.currentSchemaVersion,
        Set(archive.events.map(\.id)).count == archive.events.count,
        archive.events.allSatisfy { $0.schemaVersion == DiagnosticEvent.currentSchemaVersion }
      else { throw DiagnosticEventStoreError.invalidArchive }
      return archive.events
    } catch let error as DiagnosticEventStoreError {
      throw error
    } catch {
      throw DiagnosticEventStoreError.invalidArchive
    }
  }
}

private struct DiagnosticEventArchive: Codable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let events: [DiagnosticEvent]

  init(events: [DiagnosticEvent]) {
    schemaVersion = Self.currentSchemaVersion
    self.events = events
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case events
  }
}
