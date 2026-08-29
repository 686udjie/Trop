//
//  DiscordTokenStore.swift
//  Trop
//

import Foundation
import Security

/// Keychain-backed Discord OAuth tokens.
enum DiscordTokenStore {
    private static let key = "integrations.discord.oauth"
    private static let storage = KeychainStorage()

    struct Tokens: Codable, Equatable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: TimeInterval
        var username: String?
        var userId: String?

        var isExpired: Bool {
            guard expiresAt > 0 else { return false }
            return Date().timeIntervalSince1970 >= expiresAt - 60
        }

        var hasAccessToken: Bool {
            !accessToken.isEmpty
        }
    }

    static func load() -> Tokens? {
        do {
            return try storageLoad()
        } catch {
            return nil
        }
    }

    static func save(_ tokens: Tokens) throws {
        try storage.save(tokens, for: key)
    }

    static func clear() throws {
        try storage.delete(for: key)
    }

    private static func storageLoad() throws -> Tokens {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainStorage.serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { throw KeychainError.itemNotFound }
        guard status == errSecSuccess else { throw KeychainError.unhandledError(status) }
        guard let data = result as? Data else { throw KeychainError.invalidData }
        return try JSONDecoder().decode(Tokens.self, from: data)
    }
}
