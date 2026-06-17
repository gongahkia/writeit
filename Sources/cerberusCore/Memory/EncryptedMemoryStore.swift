import CryptoKit
import Foundation

public struct MemoryRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let content: String
    public let tags: [String]

    public init(id: UUID = UUID(), timestamp: Date = Date(), content: String, tags: [String] = []) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
        self.tags = tags
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

        return try text
            .split(separator: "\n")
            .map { line in
                guard let sealedData = Data(base64Encoded: String(line)) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
                let opened = try AES.GCM.open(sealedBox, using: try key())
                return try decoder.decode(MemoryRecord.self, from: opened)
            }
    }

    public func search(query: String, limit: Int) throws -> [MemoryRecord] {
        let terms = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        return try records()
            .filter { record in
                guard !terms.isEmpty else {
                    return true
                }
                let haystack = ([record.content] + record.tags).joined(separator: " ").lowercased()
                return terms.allSatisfy { haystack.contains($0) }
            }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
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
