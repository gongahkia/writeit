import CryptoKit
import Foundation

public struct TranscriptRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let request: String
    public let response: String
    public let toolName: String?
    public let argumentsSummary: String?
    public let promptVersion: String?
    public let modelProfile: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        request: String,
        response: String,
        toolName: String? = nil,
        argumentsSummary: String? = nil,
        promptVersion: String? = nil,
        modelProfile: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.request = request
        self.response = response
        self.toolName = toolName
        self.argumentsSummary = argumentsSummary
        self.promptVersion = promptVersion
        self.modelProfile = modelProfile
    }
}

public actor EncryptedTranscriptStore {
    private let fileURL: URL
    private let keychainStore: KeychainSecretStore
    private let fixedKeyData: Data?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        fileURL: URL = EncryptedTranscriptStore.defaultFileURL(),
        keychainStore: KeychainSecretStore = KeychainSecretStore(account: "transcript-encryption-key"),
        fixedKeyData: Data? = nil
    ) {
        self.fileURL = fileURL
        self.keychainStore = keychainStore
        self.fixedKeyData = fixedKeyData
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func append(_ record: TranscriptRecord) throws {
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

    public func records() throws -> [TranscriptRecord] {
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
                    return try decoder.decode(TranscriptRecord.self, from: opened)
                }
        } catch {
            throw EncryptedStoreRecoveryError.unreadableWithCurrentKey
        }
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
        CerberusDirectories.applicationSupportFile("transcripts.jsonl.enc")
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
