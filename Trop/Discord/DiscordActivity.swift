//
//  DiscordActivity.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import Foundation

struct DiscordActivity: Equatable {
    // 0 playing, 2 listening, 3 watching, 5 competing
    var activityType: Int = 2
    var name: String?
    var state: String
    var details: String?
    var startTimestamp: Int64 // millis since epoch; 0 if paused
    var endTimestamp: Int64?  // millis; nil if unknown
    var largeImage: String?
    var largeText: String?
    var smallImage: String?
    var smallText: String?
    var button1Label: String?
    var button1Url: String?
    var button2Label: String?
    var button2Url: String?

    static let typePlaying = 0
    static let typeListening = 2
    static let typeWatching = 3
    static let typeCompeting = 5
}
