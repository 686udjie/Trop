//
//  CookieStore.swift
//  Trop
//
//  Created by 686udjie on 28/06/2026.
//

import Foundation

// Manages persistence of auth tokens and cookies via UserDefaults
struct CookieStore {
    private static let cookiesKey = "auth_cookies"
    private static let sapisidKey = "auth_sapisid"
    private static let visitorDataKey = "auth_visitor_data"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var cookies: [String: String] {
        defaults.dictionary(forKey: Self.cookiesKey) as? [String: String] ?? [:]
    }

    var sapisid: String? {
        defaults.string(forKey: Self.sapisidKey)
    }

    var visitorData: String? {
        defaults.string(forKey: Self.visitorDataKey)
    }

    var isLoggedIn: Bool {
        sapisid != nil
    }

    // Saves auth state after successful login
    func save(cookies: [String: String], sapisid: String?, visitorData: String?) {
        defaults.set(cookies, forKey: Self.cookiesKey)
        defaults.set(sapisid, forKey: Self.sapisidKey)
        defaults.set(visitorData, forKey: Self.visitorDataKey)
    }

    // Clears all stored auth data on logout
    func clear() {
        defaults.removeObject(forKey: Self.cookiesKey)
        defaults.removeObject(forKey: Self.sapisidKey)
        defaults.removeObject(forKey: Self.visitorDataKey)
    }
}
