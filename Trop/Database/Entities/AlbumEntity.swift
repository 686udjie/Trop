//
// AlbumEntity.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

struct AlbumEntity: Codable, Hashable, FetchableRecord, PersistableRecord {
    var id: String
    var title: String
    var playlistId: String?
    var thumbnailUrl: String?
    var songCount: Int
    var duration: Int
    var bookmarkedAt: Date?

    static let databaseTableName = "album"

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case playlistId = "playlist_id"
        case thumbnailUrl = "thumbnail_url"
        case songCount = "song_count"
        case duration
        case bookmarkedAt = "bookmarked_at"
    }
}
