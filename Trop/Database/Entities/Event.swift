//
// Event.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

struct Event: Codable, Hashable, FetchableRecord, PersistableRecord {
    var id: Int?
    var songId: String
    var timestamp: Date
    var playTime: Int64

    static let databaseTableName = "event"

    enum CodingKeys: String, CodingKey {
        case id
        case songId = "song_id"
        case timestamp
        case playTime = "play_time"
    }
}
