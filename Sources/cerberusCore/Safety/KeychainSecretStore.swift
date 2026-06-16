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

public struct KeychainSecretStore: Sendable {
    public let service: String
    public let account: String

    public init(service: String = CerberusCore.bundleIdentifier, account: String) {
        self.service = service
        self.account = account
    }

    public func data() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainSecretStoreError.osStatus(status)
        }
        guard let data = item as? Data else {
            throw KeychainSecretStoreError.unexpectedData
        }
        return data
    }

    public func save(_ data: Data) throws {
        var query = baseQuery()
        let attributes = [kSecValueData as String: data] as CFDictionary
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes)

        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw KeychainSecretStoreError.osStatus(updateStatus)
        }

        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainSecretStoreError.osStatus(addStatus)
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
