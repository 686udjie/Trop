//
//  SecureStore.swift
//  Trop
//
// Created by 686udjie on 12/09/2026.
//

import Foundation
import Security

/// Thin wrapper over the Security framework for generic-password items.
/// Consolidates the copy-pasted `SecItemDelete`/`SecItemAdd`/
/// `SecItemCopyMatching` blocks from LastFMTokenStore, DiscordTokenStore and
/// KeychainStorage. Throwing core — callers keep their own contract
/// (token stores map failures to nil, KeychainStorage maps to KeychainError).
struct SecureStore: Sendable {
    let service: String

    func save(_ data: Data, for key: String) throws {
        var query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureStoreError.unhandled(status)
        }
    }

    func load(for key: String) throws -> Data {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw status == errSecItemNotFound ? SecureStoreError.notFound : SecureStoreError.unhandled(status)
        }
        return data
    }

    func delete(for key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.unhandled(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

enum SecureStoreError: Error {
    case notFound
    case unhandled(OSStatus)
}
