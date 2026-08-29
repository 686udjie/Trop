//
//  DiscordExternalAssets.swift
//  Trop
//

import Foundation

/// Resolves remote image URLs to Discord `mp:` external asset references.
actor DiscordExternalAssets {
    static let shared = DiscordExternalAssets()

    private var cache: [String: String] = [:]
    private let session: URLSession
    private let maxCache = 128

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
    }

    func resolve(imageURL: String, appId: String, accessToken: String) async -> String? {
        guard !imageURL.isEmpty, !appId.isEmpty, !accessToken.isEmpty else { return nil }
        if imageURL.hasPrefix("mp:") { return imageURL }
        if let cached = cache[imageURL] { return cached }

        let endpoint = String(format: DiscordDefaults.externalAssetsAPI, appId)
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Trop (https://github.com/686udjie/Trop)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["urls": [imageURL]])

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                // Fallback used by classic music RPC clients when external-assets fails.
                let fallback = "mp:external/\(imageURL)"
                cache[imageURL] = fallback
                trimCache()
                return fallback
            }
            guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let path = array.first?["external_asset_path"] as? String,
                  !path.isEmpty else {
                let fallback = "mp:external/\(imageURL)"
                cache[imageURL] = fallback
                trimCache()
                return fallback
            }
            let result = path.hasPrefix("mp:") ? path : "mp:\(path)"
            cache[imageURL] = result
            trimCache()
            return result
        } catch {
            Log.discord.warning("external-assets failed: \(error.localizedDescription)")
            let fallback = "mp:external/\(imageURL)"
            cache[imageURL] = fallback
            return fallback
        }
    }

    func clearCache() {
        cache.removeAll()
    }

    private func trimCache() {
        while cache.count > maxCache {
            if let key = cache.keys.first {
                cache.removeValue(forKey: key)
            }
        }
    }
}
