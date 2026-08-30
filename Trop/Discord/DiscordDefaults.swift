//
//  DiscordDefaults.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import Foundation

enum DiscordDefaults {
    static let appId: String = "1543750462422122616"
    static let appIdInt: Int64 = 1_543_750_462_422_122_616

    static let redirectUri = "tropdiscord://oauth2/callback"
    static let redirectScheme = "tropdiscord"
    static let redirectHost = "oauth2"
    static let redirectPathPrefix = "/callback"

    static let oauthAuthorize = "https://discord.com/oauth2/authorize"
    static let oauthToken = "https://discord.com/api/v10/oauth2/token"
    // Primary scopes per portal: sdk.social_layer_presence + identify + rpc (Social SDK enabled)
    static var scopes: String {
        if let override = UserDefaults.standard.string(forKey: "discordScopesOverride"),
           !override.trimmingCharacters(in: .whitespaces).isEmpty {
            if override == "identify" || override == "identify rpc rpc.activities.write" {
                return "sdk.social_layer_presence identify rpc rpc.activities.write"
            }
            return override
        }
        return "sdk.social_layer_presence identify rpc rpc.activities.write"
    }
    static let scopesFallback = "sdk.social_layer_presence identify rpc rpc.activities.write"
    static let gatewayUrl = "wss://gateway.discord.gg/?v=10&encoding=json"

    // Activity / presence defaults
    static let youtubeWatchUrl = "https://music.youtube.com/watch?v="
    static let button1Label = "Listen on YouTube Music"
    static let button1UrlTemplate = "https://music.youtube.com/watch?v={song.id}"
    static let button2Label = "Visit Trop"
    static let button2Url = "https://github.com/686udjie/Trop"
    static let stateTemplate = "{artist.name}"
    static let detailsTemplate = "{song.name}"
    static let activityType = "2"
    static let activityName = ""
    static let userStatus = "online"
    static let statusIdle = "idle"
    static let statusDnd = "dnd"
    static let activityTypeListening = "2"
    static let activityTypePlaying = "0"
    static let activityTypeWatching = "3"
    static let activityTypeCompeting = "5"
    static let unknownArtist = "Unknown Artist"
    static let unknownAlbum = "Unknown Album"

    // External assets API
    static let externalAssetsApiTemplate = "https://discord.com/api/v9/applications/%@/external-assets"

    // User-Agent / Super Properties (mirrors Android)
    static let userAgent = "Discord-Android/314013;RNA"
    static let clientVersion = "314.13 - Stable"
    static let clientBuildNumber = 314013
    static let releaseChannel = "googleRelease"
}
