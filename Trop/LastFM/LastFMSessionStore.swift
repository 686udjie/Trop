//
//  LastFMSessionStore.swift
//  Trop
//

import Foundation

/// Persists Last.fm session key in UserDefaults (Metrolist-style).
enum LastFMSessionStore {
    private static let defaults = UserDefaults.standard

    private enum Keys {
        static let sessionKey = "lastfm.sessionKey"
        static let username = "lastfm.username"
    }

    static var sessionKey: String? {
        get { defaults.string(forKey: Keys.sessionKey) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Keys.sessionKey)
            } else {
                defaults.removeObject(forKey: Keys.sessionKey)
            }
        }
    }

    static var username: String? {
        get { defaults.string(forKey: Keys.username) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Keys.username)
            } else {
                defaults.removeObject(forKey: Keys.username)
            }
        }
    }

    static var isLoggedIn: Bool {
        !(sessionKey ?? "").isEmpty
    }

    static func save(sessionKey: String, username: String) {
        self.sessionKey = sessionKey
        self.username = username
    }

    static func clear() {
        sessionKey = nil
        username = nil
    }
}
