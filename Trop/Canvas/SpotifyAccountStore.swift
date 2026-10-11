//
//  SpotifyAccountStore.swift
//  Trop
//
//  Created by 686udjie on 11/10/2026.
//

import Foundation
import WebKit

/// The public profile confirmed at login time.
struct SpotifyProfile: Equatable {
    let userId: String
    let displayName: String
    let avatarURL: URL?
    let product: String?
}

final class SpotifyAccountStore: @unchecked Sendable {
    static let shared = SpotifyAccountStore()

    enum DefaultsKeys {
        static let userId = "spotify.userId"
        static let displayName = "spotify.displayName"
        static let avatarURL = "spotify.avatarURL"
        static let product = "spotify.product"
    }

    private let store = SecureStore(service: "com.trop.spotify.canvas")
    private let cookieAccount = "spDc"
    private let queue = DispatchQueue(label: "com.trop.SpotifyAccountStore", attributes: .concurrent)
    private var cachedCookie: String?

    private init() {}

    /// The session cookie, or nil when logged out.
    func cookie() -> String? {
        queue.sync {
            if let cached = cachedCookie { return cached.isEmpty ? nil : cached }
            guard let data = try? store.load(for: cookieAccount),
                  let value = String(data: data, encoding: .utf8), !value.isEmpty
            else { return nil }
            cachedCookie = value
            return value
        }
    }

    var isLoggedIn: Bool { cookie() != nil }

    func profile() -> SpotifyProfile? {
        let defaults = UserDefaults.standard
        guard let userId = defaults.string(forKey: DefaultsKeys.userId), !userId.isEmpty else { return nil }
        return SpotifyProfile(
            userId: userId,
            displayName: defaults.string(forKey: DefaultsKeys.displayName) ?? userId,
            avatarURL: defaults.string(forKey: DefaultsKeys.avatarURL).flatMap(URL.init(string:)),
            product: defaults.string(forKey: DefaultsKeys.product)
        )
    }

    func store(cookie: String, profile: SpotifyProfile) {
        queue.sync(flags: .barrier) {
            saveCookie(cookie)
            let defaults = UserDefaults.standard
            defaults.set(profile.userId, forKey: DefaultsKeys.userId)
            defaults.set(profile.displayName, forKey: DefaultsKeys.displayName)
            defaults.set(profile.avatarURL?.absoluteString, forKey: DefaultsKeys.avatarURL)
            defaults.set(profile.product, forKey: DefaultsKeys.product)
        }
    }

    func storeSession(cookie: String) {
        queue.sync(flags: .barrier) { saveCookie(cookie) }
    }

    private func saveCookie(_ cookie: String) {
        if let data = cookie.data(using: .utf8) { try? store.save(data, for: cookieAccount) }
        cachedCookie = cookie
    }

    func clear() {
        queue.sync(flags: .barrier) {
            try? store.delete(for: cookieAccount)
            cachedCookie = nil
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: DefaultsKeys.userId)
            defaults.removeObject(forKey: DefaultsKeys.displayName)
            defaults.removeObject(forKey: DefaultsKeys.avatarURL)
            defaults.removeObject(forKey: DefaultsKeys.product)
        }
    }

    static func fetchProfile(token: String, clientToken: String? = nil) async -> SpotifyProfile? {
        guard let url = URL(string: "https://api.spotify.com/v1/me") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let clientToken { request.setValue(clientToken, forHTTPHeaderField: "Client-Token") }
        request.setValue(CanvasEndpoints.webUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://open.spotify.com", forHTTPHeaderField: "Origin")
        request.setValue("https://open.spotify.com/", forHTTPHeaderField: "Referer")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return nil
        }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? -1
        guard status == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userId = json["id"] as? String, !userId.isEmpty
        else {
            return nil
        }
        let images = (json["images"] as? [[String: Any]])?.compactMap { $0["url"] as? String }
        return SpotifyProfile(
            userId: userId,
            displayName: (json["display_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? userId,
            avatarURL: images?.first.flatMap(URL.init(string:)),
            product: json["product"] as? String
        )
    }

    static func deleteWebCookies() async {
        let store = await MainActor.run { WKWebsiteDataStore.default().httpCookieStore }
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                store.getAllCookies { cookies in
                    continuation.resume(returning: cookies)
                }
            }
        }
        for cookie in cookies where cookie.domain.contains("spotify.com") {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async {
                    store.delete(cookie) {
                        continuation.resume()
                    }
                }
            }
        }
    }
}
