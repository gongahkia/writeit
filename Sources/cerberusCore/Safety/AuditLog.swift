import CryptoKit
import Foundation

public struct AuditLogEntry: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let toolName: String
    public let argumentsSummary: String
    public let resultSummary: String
    public let previousHash: String
    public let hash: String
    public let signature: String?

    public init(
        timestamp: Date = Date(),
        toolName: String,
        argumentsSummary: String,
        resultSummary: String,
        previousHash: String,
        signature: String? = nil
    ) {
        self.timestamp = timestamp
        self.toolName = toolName
        self.argumentsSummary = argumentsSummary
        self.resultSummary = resultSummary
        self.previousHash = previousHash
        hash = Self.hash(
            timestamp: timestamp,
            toolName: toolName,
            argumentsSummary: argumentsSummary,
            resultSummary: resultSummary,
            previousHash: previousHash
        )
        self.signature = signature
    }

    public static func hash(
        timestamp: Date,
        toolName: String,
        argumentsSummary: String,
        resultSummary: String,
        previousHash: String
    ) -> String {
        let payload = [
            ISO8601DateFormatter().string(from: timestamp),
            toolName,
            argumentsSummary,
            resultSummary,
            previousHash
        ].joined(separator: "\u{1f}")

        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func signed(using key: SymmetricKey) -> AuditLogEntry {
        AuditLogEntry(
            timestamp: timestamp,
            toolName: toolName,
            argumentsSummary: argumentsSummary,
            resultSummary: resultSummary,
            previousHash: previousHash,
            signature: Self.signature(for: hash, using: key)
        )
    }

    public func isSignatureValid(using key: SymmetricKey) -> Bool {
        signature == Self.signature(for: hash, using: key)
    }

    public static func signature(for hash: String, using key: SymmetricKey) -> String {
        let authenticationCode = HMAC<SHA256>.authenticationCode(for: Data(hash.utf8), using: key)
        return Data(authenticationCode).map { String(format: "%02x", $0) }.joined()
    }
}

public actor AuditLog {
    private let fileURL: URL
    private let keychainStore: KeychainSecretStore
    private let fixedSigningKeyData: Data?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        fileURL: URL = AuditLog.defaultFileURL(),
        keychainStore: KeychainSecretStore = KeychainSecretStore(account: "audit-signing-key"),
        fixedSigningKeyData: Data? = nil
    ) {
        self.fileURL = fileURL
        self.keychainStore = keychainStore
        self.fixedSigningKeyData = fixedSigningKeyData
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    @discardableResult
    public func append(toolName: String, argumentsSummary: String, resultSummary: String) throws -> AuditLogEntry {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let entry = AuditLogEntry(
            toolName: toolName,
            argumentsSummary: argumentsSummary,
            resultSummary: resultSummary,
            previousHash: try lastHash()
        ).signed(using: try signingKey())
        let data = try encoder.encode(entry)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n".utf8))
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: fileURL, options: .atomic)
        }

        return entry
    }

    public func entries() throws -> [AuditLogEntry] {
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
                guard let lineData = line.data(using: .utf8) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return try decoder.decode(AuditLogEntry.self, from: lineData)
            }
    }

    public func recentEntries(limit: Int = 5) throws -> [AuditLogEntry] {
        Array(try entries().suffix(max(0, limit)).reversed())
    }

    public func signaturesAreValid() throws -> Bool {
        let key = try signingKey()
        return try entries().allSatisfy { $0.isSignatureValid(using: key) }
    }

    public static func defaultFileURL() -> URL {
        CerberusDirectories.applicationSupportFile("audit.log")
    }

    private func lastHash() throws -> String {
        try entries().last?.hash ?? "genesis"
    }

    private func signingKey() throws -> SymmetricKey {
        if let fixedSigningKeyData {
            return SymmetricKey(data: fixedSigningKeyData)
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
