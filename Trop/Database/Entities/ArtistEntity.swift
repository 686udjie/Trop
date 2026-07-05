//
// ArtistEntity.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

struct ArtistEntity: Codable, Hashable, FetchableRecord, PersistableRecord {
    var id: String
    var name: String
    var thumbnailUrl: String?
    var bookmarkedAt: Date?
    var isPodcastChannel: Bool
    var channelId: String?

    static let databaseTableName = "artist"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case thumbnailUrl = "thumbnail_url"
        case bookmarkedAt = "bookmarked_at"
        case isPodcastChannel = "is_podcast_channel"
        case channelId = "channel_id"
    }
}
