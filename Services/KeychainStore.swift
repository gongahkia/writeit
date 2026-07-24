import Foundation
import Security

enum KeychainStore {
  static let service = "com.gongahkia.writeit"

  static func data(for account: String) throws -> Data? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw KeychainError.status(status) }
    guard let data = result as? Data else { throw KeychainError.invalidResult }
    return data
  }

  static func set(_ data: Data, for account: String) throws {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
    let update = [kSecValueData: data] as CFDictionary
    let updateStatus = SecItemUpdate(query as CFDictionary, update)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else { throw KeychainError.status(updateStatus) }
    let item: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecValueData: data,
      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]
    let status = SecItemAdd(item as CFDictionary, nil)
    if status == errSecDuplicateItem {
      let retryStatus = SecItemUpdate(query as CFDictionary, update)
      guard retryStatus == errSecSuccess else { throw KeychainError.status(retryStatus) }
      return
    }
    guard status == errSecSuccess else { throw KeychainError.status(status) }
  }

  static func delete(_ account: String) throws {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.status(status)
    }
  }
}

enum KeychainError: LocalizedError, Equatable {
  case invalidResult
  case status(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidResult: "Secure storage returned an invalid value."
    case .status: "Secure storage could not complete the request."
    }
  }
}
