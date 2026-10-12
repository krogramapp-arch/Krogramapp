import Foundation
import Security

enum KeychainError: Error {
    case failed(OSStatus)
    case existingDatabaseKeyMissing
}

/// Minimal Keychain wrapper for small secrets (API credentials, database key).
enum Keychain {
    private static let service = "com.krogram.app"

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    static func set(_ data: Data, for key: String) throws {
        let query = baseQuery(key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.failed(updateStatus)
        }

        var item = baseQuery(key)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.failed(status) }
    }

    static func get(_ key: String) throws -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.failed(status) }
        return result as? Data
    }

    static func remove(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}

/// App credentials from my.telegram.org. Stored only in the Keychain, never in the repository.
struct TelegramCredentials: Codable, Sendable, Equatable {
    let apiID: Int
    let apiHash: String

    static func isValid(apiID: Int, apiHash: String) -> Bool {
        apiID > 0 && apiHash.range(of: "^[0-9a-fA-F]{32}$", options: .regularExpression) != nil
    }
}
