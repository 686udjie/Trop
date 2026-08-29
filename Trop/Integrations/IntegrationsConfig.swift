//
//  IntegrationsConfig.swift
//  Trop
//

import Foundation

/// Loads Discord / Last.fm credentials from Trop.plist.
enum IntegrationsConfig {
    struct Values {
        var discordClientID: String
        var lastFMAPIKey: String
        var lastFMAPISecret: String
    }

    static func load() -> Values {
        guard let url = Bundle.main.url(forResource: "Trop", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
            Log.settings.warning("Trop.plist missing — integrations will stay uninitialized")
            return Values(discordClientID: "", lastFMAPIKey: "", lastFMAPISecret: "")
        }
        return Values(
            discordClientID: (dict["DiscordClientID"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            lastFMAPIKey: (dict["LastFMAPIKey"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            lastFMAPISecret: (dict["LastFMAPISecret"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
