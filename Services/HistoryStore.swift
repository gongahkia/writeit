import Combine
import CryptoKit
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
  @Published private(set) var entries: [HistoryEntry]

  private let fileURL: URL
  private let key: SymmetricKey

  init() {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("WriteIt", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    fileURL = base.appendingPathComponent("history.sealed")
    key = Self.loadKey()
    entries = Self.load(from: fileURL, key: key)
  }

  func append(text: String, strokes: [InkStroke], mode: HistoryMode, source: String) {
    guard mode != .off else { return }
    entries.insert(HistoryEntry(text: text, strokes: mode == .full ? strokes : nil, source: source), at: 0)
    persist()
  }

  func delete(_ entry: HistoryEntry) {
    entries.removeAll { $0.id == entry.id }
    persist()
  }

  func clear() {
    entries = []
    persist()
  }

  func removeEntries(olderThan date: Date) {
    let originalCount = entries.count
    entries.removeAll { $0.createdAt < date }
    if entries.count != originalCount { persist() }
  }

  private func persist() {
    guard let encoded = try? JSONEncoder().encode(entries), let sealed = try? AES.GCM.seal(encoded, using: key).combined else { return }
    try? sealed.write(to: fileURL, options: .atomic)
  }

  private static func loadKey() -> SymmetricKey {
    if let data = KeychainStore.data(for: "history-key") { return SymmetricKey(data: data) }
    let key = SymmetricKey(size: .bits256)
    let data = key.withUnsafeBytes { Data($0) }
    try? KeychainStore.set(data, for: "history-key")
    return key
  }

  private static func load(from url: URL, key: SymmetricKey) -> [HistoryEntry] {
    guard let data = try? Data(contentsOf: url), let box = try? AES.GCM.SealedBox(combined: data), let clear = try? AES.GCM.open(box, using: key), let entries = try? JSONDecoder().decode([HistoryEntry].self, from: clear) else { return [] }
    return entries
  }
}
