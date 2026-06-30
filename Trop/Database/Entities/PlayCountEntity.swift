//
// PlayCountEntity.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

struct PlayCountEntity: Codable, Hashable, FetchableRecord, PersistableRecord {
    var songId: String
    var year: Int
    var month: Int
    var count: Int

    static let databaseTableName = "play_count"

    enum CodingKeys: String, CodingKey {
        case songId = "song_id"
        case year
        case month
        case count
    }
}
