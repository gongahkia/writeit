import Combine
import Foundation

enum AnonymousMetricKind: String, Codable, CaseIterable, Sendable {
  case runtimeStarted
  case runtimeStopped
}

struct AnonymousMetricEvent: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let occurredAt: Date
  let kind: AnonymousMetricKind

  init(occurredAt: Date, kind: AnonymousMetricKind) {
    schemaVersion = Self.currentSchemaVersion
    self.occurredAt = occurredAt
    self.kind = kind
  }

  init(from decoder: any Decoder) throws {
    let allKeys = try decoder.container(keyedBy: AnonymousMetricCodingKey.self).allKeys
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard Set(allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.stringValue))) else {
      throw AnonymousMetricsQueueError.invalidQueue
    }
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    occurredAt = try container.decode(Date.self, forKey: .occurredAt)
    kind = try container.decode(AnonymousMetricKind.self, forKey: .kind)
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion = "schema_version"
    case occurredAt = "occurred_at"
    case kind
  }
}

struct AnonymousMetricsRetentionPolicy: Equatable, Sendable {
  static let `default` = Self(maximumAge: 7 * 24 * 60 * 60, maximumEvents: 100)

  let maximumAge: TimeInterval
  let maximumEvents: Int

  init(maximumAge: TimeInterval, maximumEvents: Int) {
    precondition(maximumAge > 0)
    precondition(maximumEvents > 0)
    self.maximumAge = maximumAge
    self.maximumEvents = maximumEvents
  }

  func retained(_ events: [AnonymousMetricEvent], at date: Date) -> [AnonymousMetricEvent] {
    Array(
      events
        .filter { $0.occurredAt >= date.addingTimeInterval(-maximumAge) }
        .sorted { $0.occurredAt < $1.occurredAt }
        .suffix(maximumEvents)
    )
  }
}

enum AnonymousMetricsQueueError: LocalizedError, Equatable {
  case invalidQueue
  case persistenceFailed

  var errorDescription: String? {
    switch self {
    case .invalidQueue: "Saved anonymous metrics could not be read."
    case .persistenceFailed: "WriteIt could not save anonymous metrics."
    }
  }
}

enum MetricsQueueStore {
  static var defaultDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("WriteIt/Metrics", isDirectory: true)
  }

  static func erase(at directory: URL) throws {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    do {
      try FileManager.default.removeItem(at: directory)
    } catch {
      throw LocalDataDeletionError.failed(.metrics)
    }
  }
}

@MainActor
final class AnonymousMetricsQueue: ObservableObject {
  @Published private(set) var events: [AnonymousMetricEvent]
  @Published private(set) var error: AppErrorPresentation?

  private let fileURL: URL
  private let retentionPolicy: AnonymousMetricsRetentionPolicy
  private let now: () -> Date
  private var hasConsent: Bool
  private var storageAvailable: Bool

  init(
    directory: URL = MetricsQueueStore.defaultDirectory,
    retentionPolicy: AnonymousMetricsRetentionPolicy = .default,
    hasConsent: Bool = false,
    now: @escaping () -> Date = Date.init
  ) {
    fileURL = directory.appendingPathComponent("queue.json")
    self.retentionPolicy = retentionPolicy
    self.now = now
    self.hasConsent = hasConsent
    storageAvailable = false
    events = []
    error = nil
    do {
      if hasConsent { try enableQueue() }
      else { try erasePersistedEvents() }
      storageAvailable = true
    } catch {
      self.error = .persistence(error)
    }
  }

  func enqueue(_ kind: AnonymousMetricKind, at occurredAt: Date? = nil) {
    guard hasConsent, storageAvailable else { return }
    let updated = retentionPolicy.retained(
      events + [AnonymousMetricEvent(occurredAt: occurredAt ?? now(), kind: kind)], at: now())
    do {
      try persist(updated)
      events = updated
      error = nil
    } catch {
      self.error = .persistence(error)
    }
  }

  func setConsent(_ hasConsent: Bool) {
    guard self.hasConsent != hasConsent else { return }
    self.hasConsent = hasConsent
    do {
      if hasConsent { try enableQueue() }
      else {
        try erasePersistedEvents()
        events = []
      }
      storageAvailable = true
      error = nil
    } catch {
      storageAvailable = false
      self.error = .persistence(error)
    }
  }

  func erase() throws {
    do {
      try erasePersistedEvents()
      events = []
      error = nil
      storageAvailable = true
    } catch {
      self.error = .persistence(error)
      throw error
    }
  }

  func clearError() { error = nil }

  private func persist(_ events: [AnonymousMetricEvent]) throws {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(AnonymousMetricsArchive(events: events)).write(
        to: fileURL, options: .atomic)
    } catch {
      throw AnonymousMetricsQueueError.persistenceFailed
    }
  }

  private func enableQueue() throws {
    let loaded = try Self.load(from: fileURL)
    let retained = retentionPolicy.retained(loaded, at: now())
    events = retained
    if retained != loaded { try persist(retained) }
  }

  private func erasePersistedEvents() throws {
    try MetricsQueueStore.erase(at: fileURL.deletingLastPathComponent())
  }

  private static func load(from fileURL: URL) throws -> [AnonymousMetricEvent] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    do {
      let archive = try JSONDecoder().decode(
        AnonymousMetricsArchive.self, from: Data(contentsOf: fileURL))
      guard archive.schemaVersion == AnonymousMetricsArchive.currentSchemaVersion,
        archive.events.allSatisfy({ $0.schemaVersion == AnonymousMetricEvent.currentSchemaVersion })
      else { throw AnonymousMetricsQueueError.invalidQueue }
      return archive.events
    } catch let error as AnonymousMetricsQueueError {
      throw error
    } catch {
      throw AnonymousMetricsQueueError.invalidQueue
    }
  }
}

private struct AnonymousMetricsArchive: Codable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let events: [AnonymousMetricEvent]

  init(events: [AnonymousMetricEvent]) {
    schemaVersion = Self.currentSchemaVersion
    self.events = events
  }

  init(from decoder: any Decoder) throws {
    let allKeys = try decoder.container(keyedBy: AnonymousMetricCodingKey.self).allKeys
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard Set(allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.stringValue))) else {
      throw AnonymousMetricsQueueError.invalidQueue
    }
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    events = try container.decode([AnonymousMetricEvent].self, forKey: .events)
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion = "schema_version"
    case events
  }
}

private struct AnonymousMetricCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
    intValue = nil
  }

  init?(intValue: Int) {
    stringValue = "\(intValue)"
    self.intValue = intValue
  }
}
