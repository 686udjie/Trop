//
// PlaylistEntity.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

struct PlaylistEntity: Codable, Hashable, FetchableRecord, PersistableRecord {
    var id: String
    var browseId: String?
    var name: String
    var thumbnailUrl: String?
    var isEditable: Bool
    var bookmarkedAt: Date?
    var remoteSongCount: Int?
    var isAutoSync: Bool = false

    static let databaseTableName = "playlist"

    enum CodingKeys: String, CodingKey {
        case id
        case browseId = "browse_id"
        case name
        case thumbnailUrl = "thumbnail_url"
        case isEditable = "is_editable"
        case bookmarkedAt = "bookmarked_at"
        case remoteSongCount = "remote_song_count"
        case isAutoSync = "is_auto_sync"
    }
}
