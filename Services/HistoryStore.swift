import Combine
import CryptoKit
import Foundation

struct HistoryArchive: Codable, Equatable {
  static let currentVersion = 1

  let version: Int
  let entries: [HistoryEntry]
}

enum HistoryStoreError: LocalizedError, Equatable {
  case archiveUnreadable
  case directoryUnavailable
  case encryptionFailed
  case keyUnavailable
  case serializationFailed
  case storageUnavailable
  case unsupportedArchive
  case writeFailed

  var errorDescription: String? {
    switch self {
    case .archiveUnreadable: "Saved history could not be read."
    case .directoryUnavailable: "WriteIt could not prepare local history storage."
    case .encryptionFailed: "WriteIt could not encrypt local history."
    case .keyUnavailable: "WriteIt could not access the key for local history."
    case .serializationFailed: "WriteIt could not prepare local history for saving."
    case .storageUnavailable: "Local history cannot be changed until its storage error is resolved."
    case .unsupportedArchive: "Saved history uses an unsupported format."
    case .writeFailed: "WriteIt could not save local history."
    }
  }
}

@MainActor
final class HistoryStore: ObservableObject {
  @Published private(set) var entries: [HistoryEntry]
  @Published private(set) var error: AppErrorPresentation?

  private let fileURL: URL
  private var key: SymmetricKey?
  private var storageAvailable: Bool

  init(fileURL: URL? = nil, key: SymmetricKey? = nil) {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("WriteIt", isDirectory: true)
    let resolvedFileURL = fileURL ?? base.appendingPathComponent("history.sealed")
    self.fileURL = resolvedFileURL
    self.key = nil
    self.storageAvailable = false
    self.entries = []
    self.error = nil
    do {
      do {
        try FileManager.default.createDirectory(
          at: resolvedFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      } catch {
        throw HistoryStoreError.directoryUnavailable
      }
      let resolvedKey = try key ?? Self.loadKey()
      self.key = resolvedKey
      let loaded = try Self.load(from: resolvedFileURL, key: resolvedKey)
      entries = loaded.entries
      if loaded.requiresMigration { try persist(entries) }
      storageAvailable = true
    } catch {
      record(error)
    }
  }

  func append(
    text: String,
    strokes: [InkStroke],
    mode: HistoryMode,
    source: String,
    confidence: Float? = nil,
    recognitionDuration: TimeInterval? = nil
  ) {
    guard mode != .off else { return }
    append(
      HistoryEntry(
        text: text,
        strokes: mode == .full ? strokes : nil,
        source: source,
        confidence: confidence,
        recognitionDuration: recognitionDuration
      ))
  }

  func append(_ entry: HistoryEntry) {
    replaceEntries([entry] + entries)
  }

  func delete(_ entry: HistoryEntry) {
    replaceEntries(entries.filter { $0.id != entry.id })
  }

  func clear() {
    replaceEntries([])
  }

  func removeEntries(olderThan date: Date) {
    let retainedEntries = entries.filter { $0.createdAt >= date }
    if retainedEntries.count != entries.count { replaceEntries(retainedEntries) }
  }

  func clearError() { error = nil }

  private func replaceEntries(_ updatedEntries: [HistoryEntry]) {
    guard storageAvailable else {
      if error == nil { record(HistoryStoreError.storageUnavailable) }
      return
    }
    do {
      try persist(updatedEntries)
      entries = updatedEntries
      error = nil
    } catch {
      record(error)
    }
  }

  private func persist(_ entries: [HistoryEntry]) throws {
    guard let key else { throw HistoryStoreError.keyUnavailable }
    let archive = HistoryArchive(version: HistoryArchive.currentVersion, entries: entries)
    let encoded: Data
    do {
      encoded = try JSONEncoder().encode(archive)
    } catch {
      throw HistoryStoreError.serializationFailed
    }
    let sealed: Data
    do {
      guard let combined = try AES.GCM.seal(encoded, using: key).combined else {
        throw HistoryStoreError.encryptionFailed
      }
      sealed = combined
    } catch let error as HistoryStoreError {
      throw error
    } catch {
      throw HistoryStoreError.encryptionFailed
    }
    do {
      try sealed.write(to: fileURL, options: .atomic)
      AppLog.history.debug("history_persisted")
    } catch {
      throw HistoryStoreError.writeFailed
    }
  }

  private static func loadKey() throws -> SymmetricKey {
    if let data = try KeychainStore.data(for: "history-key") { return SymmetricKey(data: data) }
    let key = SymmetricKey(size: .bits256)
    let data = key.withUnsafeBytes { Data($0) }
    try KeychainStore.set(data, for: "history-key")
    return key
  }

  private static func load(from url: URL, key: SymmetricKey) throws -> (
    entries: [HistoryEntry], requiresMigration: Bool
  ) {
    guard FileManager.default.fileExists(atPath: url.path) else { return ([], false) }
    do {
      let data = try Data(contentsOf: url)
      let box = try AES.GCM.SealedBox(combined: data)
      let clear = try AES.GCM.open(box, using: key)
      do {
        let archive = try JSONDecoder().decode(HistoryArchive.self, from: clear)
        guard archive.version == HistoryArchive.currentVersion else {
          throw HistoryStoreError.unsupportedArchive
        }
        return (archive.entries, false)
      } catch let error as HistoryStoreError {
        throw error
      } catch {
        let legacyEntries = try JSONDecoder().decode([HistoryEntry].self, from: clear)
        return (legacyEntries, true)
      }
    } catch {
      if let error = error as? HistoryStoreError { throw error }
      throw HistoryStoreError.archiveUnreadable
    }
  }

  private func record(_ error: Error) {
    AppLog.history.error(
      "history_storage_failed type=\(AppLog.errorType(error), privacy: .public)")
    self.error = error is KeychainError
      ? .security(error)
      : .persistence(error)
  }
}
