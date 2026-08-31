//
//  LastFMDefaults.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import Foundation

enum LastFMDefaults {
    // API credentials — override via UserDefaults or Info.plist for release builds
    // For development they can be injected via TropApp initialization.
    static var apiKey: String {
        if let override = UserDefaults.standard.string(forKey: "lastfmApiKeyOverride")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty { return override }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "LASTFM_API_KEY") as? String {
            let trimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return _apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var secret: String {
        if let override = UserDefaults.standard.string(forKey: "lastfmSecretOverride")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty { return override }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "LASTFM_SECRET") as? String {
            let trimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return _secret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Fallback only — `LASTFM_API_KEY`/`LASTFM_SECRET` are injected via GH Secrets -> Info.plist at build time
    private static var _apiKey: String = ""
    private static var _secret: String = ""

    static func configure(apiKey: String, secret: String) {
        _apiKey = apiKey
        _secret = secret
    }

    static var isConfigured: Bool { !apiKey.isEmpty && !secret.isEmpty }

    static let baseUrl = "https://ws.audioscrobbler.com/2.0/"
    static let authUrlBase = "https://www.last.fm/api/auth/"

    static func authUrl(token: String) -> String {
        "\(authUrlBase)?api_key=\(apiKey)&token=\(token)"
    }

    // Scrobble defaults (mirrors Metrolist)
    static let defaultScrobbleDelayPercent: Float = 0.5
    static let defaultScrobbleMinDuration: Int = 30
    static let defaultScrobbleDelaySeconds: Int = 180

    // UserDefaults keys (keep compatible with Metrolist naming)
    static let sessionKeyKey = "lastfmSession"
    static let usernameKey = "lastfmUsername"
    static let scrobblingEnabledKey = "lastfmScrobblingEnable"
    static let useNowPlayingKey = "lastfmUseNowPlaying"
    static let useSendLikesKey = "lastfmUseSendLikes"
    static let scrobbleDelayPercentKey = "scrobbleDelayPercent"
    static let scrobbleMinDurationKey = "scrobbleMinSongDuration"
    static let scrobbleDelaySecondsKey = "scrobbleDelaySeconds"
}
