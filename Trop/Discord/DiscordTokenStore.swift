//
//  DiscordTokenStore.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import Foundation
import Security

final class DiscordTokenStore: @unchecked Sendable {
    static let shared = DiscordTokenStore()

    private let service = "com.trop.discord.token"
    private let accessTokenKey = "access_token"
    private let refreshTokenKey = "refresh_token"
    private let expiresAtKey = "expires_at"
    private let deviceVendorIdKey = "device_vendor_id"
    private let clientUuidKey = "client_uuid"

    // In-memory cache to avoid Keychain roundtrips
    private var cachedAccessToken: String?
    private var cachedRefreshToken: String?
    private var cachedExpiresAt: Int64?

    private let queue = DispatchQueue(label: "com.trop.DiscordTokenStore", attributes: .concurrent)

    private init() {}

    // MARK: - Public API (mirrors Kotlin)

    func retrieve() -> String? {
        queue.sync {
            if let cached = cachedAccessToken { return cached }
            let token: String? = loadString(for: accessTokenKey)
            cachedAccessToken = token
            return token
        }
    }

    func retrieveSuspend() async -> String? { retrieve() }

    func getRefreshToken() -> String? {
        queue.sync {
            if let cached = cachedRefreshToken { return cached }
            let token: String? = loadString(for: refreshTokenKey)
            cachedRefreshToken = token
            return token
        }
    }

    func getExpiresAt() -> Int64 {
        queue.sync {
            if let cached = cachedExpiresAt { return cached }
            let val: Int64 = loadInt64(for: expiresAtKey) ?? 0
            cachedExpiresAt = val
            return val
        }
    }

    func getDeviceVendorId() -> String? { getOrCreateId(key: deviceVendorIdKey) }
    func getClientUuid() -> String? { getOrCreateId(key: clientUuidKey) }

    func store(token: String) { storeFull(accessToken: token, refreshToken: "", expiresInSec: 0) }

    func storeFull(accessToken: String, refreshToken: String, expiresInSec: Int64) {
        queue.sync(flags: .barrier) {
            saveString(accessToken, for: accessTokenKey)
            self.cachedAccessToken = accessToken
            if !refreshToken.isEmpty {
                saveString(refreshToken, for: refreshTokenKey)
                self.cachedRefreshToken = refreshToken
            }
            if expiresInSec > 0 {
                let expiresAt = Int64(Date().timeIntervalSince1970) + expiresInSec
                saveInt64(expiresAt, for: expiresAtKey)
                self.cachedExpiresAt = expiresAt
            }
        }
    }

    func storeAccessToken(_ accessToken: String) {
        queue.sync(flags: .barrier) {
            saveString(accessToken, for: accessTokenKey)
            self.cachedAccessToken = accessToken
        }
    }

    func clear() {
        queue.sync(flags: .barrier) {
            delete(for: accessTokenKey)
            delete(for: refreshTokenKey)
            delete(for: expiresAtKey)
            // Keep vendor/client UUIDs across logout? Spec clears them on logout (DiscordRpcManager.logout)
            // We delete them here to match DiscordTokenStore.clear() behavior.
            delete(for: deviceVendorIdKey)
            delete(for: clientUuidKey)
            cachedAccessToken = nil
            cachedRefreshToken = nil
            cachedExpiresAt = nil
        }
    }

    // MARK: - UUID cache

    private func getOrCreateId(key: String) -> String? {
        queue.sync(flags: .barrier) {
            if let existing: String = loadString(for: key), !existing.isEmpty {
                return existing
            }
            let newId = UUID().uuidString
            saveString(newId, for: key)
            return newId
        }
    }

    // MARK: - Keychain primitives

    private func saveString(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        saveData(data, for: key)
    }

    private func loadString(for key: String) -> String? {
        guard let data = loadData(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveInt64(_ value: Int64, for key: String) {
        var v = value
        let data = Data(bytes: &v, count: MemoryLayout<Int64>.size)
        saveData(data, for: key)
    }

    private func loadInt64(for key: String) -> Int64? {
        guard let data = loadData(for: key), data.count == MemoryLayout<Int64>.size else { return nil }
        return data.withUnsafeBytes { $0.load(as: Int64.self) }
    }

    // Fallback: also support string-encoded int for migration
    private func saveData(_ data: Data, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadData(for key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func delete(for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
