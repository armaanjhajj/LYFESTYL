//
//  KeychainStore.swift
//  LYFESTYL
//
//  Connector credentials live in the iOS keychain, never in UserDefaults and never in
//  a file. A Hevy API key is a bearer credential for someone's whole training history,
//  so it gets the same treatment a password would.
//
//  Items are stored with `kSecAttrAccessibleAfterFirstUnlock` so a background refresh
//  can still reach them, but they remain unreadable while the device is locked from
//  cold boot, and `ThisDeviceOnly` keeps them out of iCloud Keychain and encrypted
//  backups. A credential the user pasted on one device should not silently appear on
//  another.
//
//  This satisfies the project rule against committed secrets: nothing is in the
//  bundle, the user supplies their own key at runtime.
//

import Foundation
import Security

/// A namespaced keychain slot.
nonisolated enum KeychainKey: String, CaseIterable, Sendable {
    case hevyAPIKey = "hevy.api_key"
    case garminAccessToken = "garmin.access_token"
    case garminRefreshToken = "garmin.refresh_token"
    case garminTokenSecret = "garmin.token_secret"
}

nonisolated enum KeychainStore {

    /// Service name under which every item is filed.
    private static let service = "com.lyfestyl.connectors"

    // MARK: - Read

    static func read(_ key: KeychainKey) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    static func has(_ key: KeychainKey) -> Bool { read(key) != nil }

    // MARK: - Write

    /// Store or replace a value. Returns false when the keychain refused the write,
    /// so the caller can tell the user rather than silently losing the credential.
    @discardableResult
    static func write(_ value: String, for key: KeychainKey) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return delete(key) }
        guard let data = trimmed.data(using: .utf8) else { return false }

        // Update in place if it already exists, otherwise add.
        let query = baseQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        guard updateStatus == errSecItemNotFound else { return false }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Delete

    @discardableResult
    static func delete(_ key: KeychainKey) -> Bool {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Wipe every connector credential, for sign-out.
    static func deleteAll() {
        for key in KeychainKey.allCases { delete(key) }
    }

    // MARK: - Helpers

    private static func baseQuery(for key: KeychainKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}
