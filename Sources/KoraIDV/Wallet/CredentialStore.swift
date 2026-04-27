// CredentialStore.swift
// KoraIDV Wallet — Keychain-backed encrypted credential storage

import Foundation
import Security

/// Secure credential storage backed by the iOS Keychain.
final class WalletCredentialStore {

    private let service = "com.korastratum.wallet"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Save

    func save(id: String, credential: StoredWalletCredential) throws {
        let data: Data
        do {
            data = try encoder.encode(credential)
        } catch {
            throw WalletError.encodingFailed
        }
        try saveRaw(id: id, data: data)
    }

    func saveRaw(id: String, data: Data) throws {
        // Delete any existing item first to avoid duplicate errors.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WalletError.storageFailed
        }
    }

    // MARK: - Load

    func load(id: String) -> StoredWalletCredential? {
        guard let data = loadRaw(id: id) else { return nil }
        return try? decoder.decode(StoredWalletCredential.self, from: data)
    }

    func loadRaw(id: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    // MARK: - Delete

    func delete(id: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WalletError.storageFailed
        }
    }

    // MARK: - List IDs

    /// Returns all credential IDs stored in the Keychain for this service.
    func listIds() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}
