//
//  DiscordActivity.swift
//  Trop
//

import Foundation

/// Payload for classic Discord Rich Presence `STATUS_UPDATE` activity.
struct DiscordActivity: Equatable {
    var name: String
    var details: String?
    var state: String?
    var largeImageURL: String?
    var largeText: String?
    var startTimestamp: Int64?
    var isPlaying: Bool
}
