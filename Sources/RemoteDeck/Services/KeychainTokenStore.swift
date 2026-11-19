import Foundation
import Security

enum KeychainTokenStoreError: Error, LocalizedError {
    case encodingFailed
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "The sign-in token could not be encoded for secure storage."
        case .keychainStatus(let status):
            return "Keychain operation failed (OSStatus \(status))."
        }
    }
}

final class KeychainTokenStore {
    private let service = "com.remotedeck.ios"
    private let account = "microsoft-oauth-tokens"

    func load() throws -> OAuthTokenSet? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainTokenStoreError.keychainStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainTokenStoreError.encodingFailed
        }
        return try JSONDecoder().decode(OAuthTokenSet.self, from: data)
    }

    func save(_ tokens: OAuthTokenSet) throws {
        guard let data = try? JSONEncoder().encode(tokens) else {
            throw KeychainTokenStoreError.encodingFailed
        }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(identity as CFDictionary, update as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = identity
            update.forEach { insert[$0.key] = $0.value }
            let status = SecItemAdd(insert as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainTokenStoreError.keychainStatus(status)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainTokenStoreError.keychainStatus(updateStatus)
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.keychainStatus(status)
        }
    }
}
