import Foundation
import Security

public enum KeychainSecretStoreError: Error, LocalizedError, Equatable {
    case unexpectedData
    case osStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unexpectedData:
            "Keychain returned an unexpected value."
        case .osStatus(let status):
            "Keychain operation failed with status \(status)."
        }
    }
}

public protocol KeychainSecretStoreOperations: Sendable {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?)
    func update(_ query: [String: Any], data: Data) -> OSStatus
    func add(_ query: [String: Any], data: Data) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

public struct KeychainSecretStore: Sendable {
    public let service: String
    public let account: String
    private let operations: any KeychainSecretStoreOperations

    public init(
        service: String = CerberusCore.bundleIdentifier,
        account: String,
        operations: any KeychainSecretStoreOperations = SystemKeychainSecretStoreOperations()
    ) {
        self.service = service
        self.account = account
        self.operations = operations
    }

    public func data() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let (status, item) = operations.copyMatching(query)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainSecretStoreError.osStatus(status)
        }
        guard let data = item else {
            throw KeychainSecretStoreError.unexpectedData
        }
        return data
    }

    public func save(_ data: Data) throws {
        var query = baseQuery()
        let updateStatus = operations.update(query, data: data)

        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw KeychainSecretStoreError.osStatus(updateStatus)
        }

        query[kSecValueData as String] = data
        let addStatus = operations.add(query, data: data)
        guard addStatus == errSecSuccess else {
            throw KeychainSecretStoreError.osStatus(addStatus)
        }
    }

    public func delete() throws {
        let status = operations.delete(baseQuery())
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.osStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public struct SystemKeychainSecretStoreOperations: KeychainSecretStoreOperations {
    public init() {}

    public func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    public func update(_ query: [String: Any], data: Data) -> OSStatus {
        let attributes = [kSecValueData as String: data] as CFDictionary
        return SecItemUpdate(query as CFDictionary, attributes)
    }

    public func add(_ query: [String: Any], data: Data) -> OSStatus {
        var query = query
        query[kSecValueData as String] = data
        return SecItemAdd(query as CFDictionary, nil)
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
