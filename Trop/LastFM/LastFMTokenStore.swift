//
//  LastFMTokenStore.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import Foundation
import Security

final class LastFMTokenStore: @unchecked Sendable {
    static let shared = LastFMTokenStore()

    private let service = "com.trop.lastfm.token"
    private let sessionKeyAccount = "sessionKey"
    private let usernameAccount = "username"
    private let subscriberAccount = "subscriber"

    private let queue = DispatchQueue(label: "com.trop.LastFMTokenStore", attributes: .concurrent)

    private var cachedSessionKey: String?
    private var cachedUsername: String?

    private init() {}

    // Mirror UserDefaults for quick reads (keep in sync)
    func retrieveSessionKey() -> String? {
        queue.sync {
            if let cached = cachedSessionKey { return cached.isEmpty ? nil : cached }
            if let fromDefaults = UserDefaults.standard.string(forKey: LastFMDefaults.sessionKeyKey),
               !fromDefaults.isEmpty {
                cachedSessionKey = fromDefaults
                return fromDefaults
            }
            let val: String? = loadString(for: sessionKeyAccount)
            cachedSessionKey = val
            return val
        }
    }

    func retrieveUsername() -> String? {
        queue.sync {
            if let cached = cachedUsername { return cached.isEmpty ? nil : cached }
            if let fromDefaults = UserDefaults.standard.string(forKey: LastFMDefaults.usernameKey),
               !fromDefaults.isEmpty {
                cachedUsername = fromDefaults
                return fromDefaults
            }
            let val: String? = loadString(for: usernameAccount)
            cachedUsername = val
            return val
        }
    }

    func store(sessionKey: String, username: String) {
        queue.sync(flags: .barrier) {
            saveString(sessionKey, for: sessionKeyAccount)
            saveString(username, for: usernameAccount)
            self.cachedSessionKey = sessionKey
            self.cachedUsername = username
            UserDefaults.standard.set(sessionKey, forKey: LastFMDefaults.sessionKeyKey)
            UserDefaults.standard.set(username, forKey: LastFMDefaults.usernameKey)
        }
    }

    func clear() {
        queue.sync(flags: .barrier) {
            delete(for: sessionKeyAccount)
            delete(for: usernameAccount)
            delete(for: subscriberAccount)
            cachedSessionKey = nil
            cachedUsername = nil
            UserDefaults.standard.removeObject(forKey: LastFMDefaults.sessionKeyKey)
            UserDefaults.standard.removeObject(forKey: LastFMDefaults.usernameKey)
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
