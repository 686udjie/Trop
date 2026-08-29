//
//  DiscordDefaults.swift
//  Trop
//

import Foundation

enum DiscordDefaults {
    static let youtubeWatchURL = "https://music.youtube.com/watch?v="
    static let button1Label = "Listen on YouTube Music"
    static let button2Label = "Visit Trop"
    static let button2URL = "https://github.com/686udjie/Trop"

    static let oauthAuthorize = "https://discord.com/oauth2/authorize"
    static let oauthToken = "https://discord.com/api/v10/oauth2/token"
    static let scopes = "openid sdk.social_layer_presence"
    static let redirectURI = "trop://oauth2/callback"

    static let gatewayURL = "wss://gateway.discord.gg/?v=10&encoding=json"
    static let externalAssetsAPI = "https://discord.com/api/v9/applications/%@/external-assets"

    static let activityTypeListening = 2
    static let unknownArtist = "Unknown Artist"
}
