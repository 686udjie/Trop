//
//  DiscordExternalAssets.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import Foundation

enum DiscordExternalAssets {
    private static let cacheMaxSize = 128
    private static var cache: [String: String] = [:]
    private static let queue = DispatchQueue(label: "com.trop.DiscordExternalAssets")

    struct ExternalAssetRequest: Codable {
        let urls: [String]
    }
    struct ExternalAssetResponse: Codable {
        let url: String?
        let externalAssetPath: String?

        enum CodingKeys: String, CodingKey {
            case url
            case externalAssetPath = "external_asset_path"
        }
    }

    static func resolve(imageUrl: String, appId: String, token: String) async -> String? {
        if imageUrl.isBlank { return nil }
        if imageUrl.hasPrefix("mp:") { return imageUrl }

        if let cached = queue.sync(execute: { cache[imageUrl] }) {
            return cached
        }

        guard let url = URL(string: String(format: DiscordDefaults.externalAssetsApiTemplate, appId)) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(DiscordDefaults.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(DiscordSuperProperties.base64, forHTTPHeaderField: "X-Super-Properties")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body = ExternalAssetRequest(urls: [imageUrl])
        guard let bodyData = try? JSONEncoder().encode(body) else { return nil }
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  !data.isEmpty else { return nil }
            let decoded = try JSONDecoder().decode([ExternalAssetResponse].self, from: data)
            guard let path = decoded.first?.externalAssetPath, !path.isEmpty else { return nil }
            let result = "mp:\(path)"
            queue.sync {
                cache[imageUrl] = result
                if cache.count > cacheMaxSize {
                    // Simple trim: remove oldest (first)
                    if let firstKey = cache.keys.first {
                        cache.removeValue(forKey: firstKey)
                    }
                }
            }
            return result
        } catch {
            return nil
        }
    }

    static func clearCache() {
        queue.sync { cache.removeAll() }
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
