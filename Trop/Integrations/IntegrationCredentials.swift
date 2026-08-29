//
//  IntegrationCredentials.swift
//  Trop
//

import Foundation

/// Keychain-backed credentials for Last.fm and Discord integrations.
enum IntegrationCredentials {
    private static let storage = KeychainStorage()

    private enum Keys {
        static let lastFM = "integrations.lastfm.credentials"
        static let discord = "integrations.discord.credentials"
    }

    // MARK: - Last.fm

    struct LastFMCredentials: Codable, Equatable {
        var apiKey: String
        var apiSecret: String
        var sessionKey: String?
        var username: String?

        var hasAPICredentials: Bool {
            !apiKey.isEmpty && !apiSecret.isEmpty
        }

        var isLoggedIn: Bool {
            guard let sessionKey, let username else { return false }
            return !sessionKey.isEmpty && !username.isEmpty
        }
    }

    static func loadLastFM() -> LastFMCredentials? {
        do {
            return try storage.loadBlocking(LastFMCredentials.self, for: Keys.lastFM)
        } catch {
            return nil
        }
    }

    static func saveLastFM(_ credentials: LastFMCredentials) throws {
        try storage.save(credentials, for: Keys.lastFM)
    }

    static func clearLastFM() throws {
        try storage.delete(for: Keys.lastFM)
    }

    // MARK: - Discord

    struct DiscordCredentials: Codable, Equatable {
        var token: String
        var username: String?
        var userId: String?

        var isLoggedIn: Bool {
            !token.isEmpty
        }
    }

    static func loadDiscord() -> DiscordCredentials? {
        do {
            return try storage.loadBlocking(DiscordCredentials.self, for: Keys.discord)
        } catch {
            return nil
        }
    }

    static func saveDiscord(_ credentials: DiscordCredentials) throws {
        try storage.save(credentials, for: Keys.discord)
    }

    static func clearDiscord() throws {
        try storage.delete(for: Keys.discord)
    }
}

private extension KeychainStorage {
    /// Synchronous load for small Codable secrets (call off the main actor when possible).
    nonisolated func loadBlocking<T: Codable>(_ type: T.Type, for key: String) throws -> T {
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
        return try JSONDecoder().decode(type, from: data)
    }
}
