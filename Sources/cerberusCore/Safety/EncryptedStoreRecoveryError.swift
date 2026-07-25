import Foundation

public enum EncryptedStoreRecoveryError: Error, LocalizedError, Equatable {
    case unreadableWithCurrentKey

    public var errorDescription: String? {
        switch self {
        case .unreadableWithCurrentKey:
            "Encrypted records cannot be read with the current key. Export from backup or reset the local store."
        }
    }
}
