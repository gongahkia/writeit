import CryptoKit
import Foundation

public enum MemoryScope: String, Codable, CaseIterable, Sendable {
    case personalPreference = "personal_preference"
    case projectFact = "project_fact"
    case temporarySessionFact = "temporary_session_fact"
}

public struct MemoryRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let content: String
    public let tags: [String]
    public let scope: MemoryScope

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        content: String,
        tags: [String] = [],
        scope: MemoryScope = .personalPreference
    ) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
        self.tags = tags
        self.scope = scope
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case content
        case tags
        case scope
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        content = try container.decode(String.self, forKey: .content)
        tags = try container.decode([String].self, forKey: .tags)
        scope = try container.decodeIfPresent(MemoryScope.self, forKey: .scope) ?? .personalPreference
    }
}

public actor EncryptedMemoryStore {
    private let fileURL: URL
    private let keychainStore: KeychainSecretStore
    private let fixedKeyData: Data?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        fileURL: URL = EncryptedMemoryStore.defaultFileURL(),
        keychainStore: KeychainSecretStore = KeychainSecretStore(account: "memory-encryption-key"),
        fixedKeyData: Data? = nil
    ) {
        self.fileURL = fileURL
        self.keychainStore = keychainStore
        self.fixedKeyData = fixedKeyData
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func append(_ record: MemoryRecord) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(record)
        let sealedBox = try AES.GCM.seal(data, using: try key())
        guard let combined = sealedBox.combined else {
            throw CocoaError(.fileWriteUnknown)
        }

        let line = Data(combined.base64EncodedString().utf8)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n".utf8))
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            try line.write(to: fileURL, options: .atomic)
        }
    }

    public func records() throws -> [MemoryRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return []
        }

        do {
            return try text
                .split(separator: "\n")
                .map { line in
                    guard let sealedData = Data(base64Encoded: String(line)) else {
                        throw EncryptedStoreRecoveryError.unreadableWithCurrentKey
                    }
                    let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
                    let opened = try AES.GCM.open(sealedBox, using: try key())
                    return try decoder.decode(MemoryRecord.self, from: opened)
                }
        } catch {
            throw EncryptedStoreRecoveryError.unreadableWithCurrentKey
        }
    }

    public func search(query: String, limit: Int) throws -> [MemoryRecord] {
        MemoryVectorIndex.ranked(records: try records(), query: query, limit: limit)
    }

    @discardableResult
    public func delete(ids: Set<UUID>) throws -> Int {
        guard !ids.isEmpty else {
            return 0
        }

        let existingRecords = try records()
        let remainingRecords = existingRecords.filter { !ids.contains($0.id) }
        let deletedCount = existingRecords.count - remainingRecords.count
        guard deletedCount > 0 else {
            return 0
        }

        try deleteAll()
        for record in remainingRecords {
            try append(record)
        }
        return deletedCount
    }

    public func exportPlaintextJSON(to outputURL: URL) throws {
        let data = try encoder.encode(records())
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
    }

    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }

    public static func defaultFileURL() -> URL {
        CerberusDirectories.applicationSupportFile("memory.jsonl.enc")
    }

    private func key() throws -> SymmetricKey {
        if let fixedKeyData {
            return SymmetricKey(data: fixedKeyData)
        }

        if let existing = try keychainStore.data() {
            return SymmetricKey(data: existing)
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try keychainStore.save(keyData)
        return key
    }
}
