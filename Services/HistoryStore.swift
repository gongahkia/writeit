import Combine
import CryptoKit
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
  @Published private(set) var entries: [HistoryEntry]

  private let fileURL: URL
  private let key: SymmetricKey

  init(fileURL: URL? = nil, key: SymmetricKey? = nil) {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("WriteIt", isDirectory: true)
    let resolvedFileURL = fileURL ?? base.appendingPathComponent("history.sealed")
    try? FileManager.default.createDirectory(
      at: resolvedFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    self.fileURL = resolvedFileURL
    self.key = key ?? Self.loadKey()
    entries = Self.load(from: resolvedFileURL, key: self.key)
  }

  func append(text: String, strokes: [InkStroke], mode: HistoryMode, source: String) {
    guard mode != .off else { return }
    append(HistoryEntry(text: text, strokes: mode == .full ? strokes : nil, source: source))
  }

  func append(_ entry: HistoryEntry) {
    entries.insert(entry, at: 0)
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
    guard let encoded = try? JSONEncoder().encode(entries),
      let sealed = try? AES.GCM.seal(encoded, using: key).combined
    else { return }
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
    guard let data = try? Data(contentsOf: url), let box = try? AES.GCM.SealedBox(combined: data),
      let clear = try? AES.GCM.open(box, using: key),
      let entries = try? JSONDecoder().decode([HistoryEntry].self, from: clear)
    else { return [] }
    return entries
  }
}
