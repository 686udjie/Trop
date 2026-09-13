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

extension PlaylistEntity {
    /// Merges fetched playlist metadata over the stored row, preserving the
    /// user's name/editability/bookmark. Used when materializing a playlist's
    /// contents (sync + detail); the liked-playlists sync keeps its own
    /// policy (name/thumbnail always refresh, bookmark defaults to now).
    static func merging(
        existing: PlaylistEntity?,
        id: String,
        browseId: String?,
        name: String,
        remoteSongCount: Int
    ) -> PlaylistEntity {
        PlaylistEntity(
            id: id,
            browseId: browseId,
            name: existing?.name ?? name,
            isEditable: existing?.isEditable ?? false,
            bookmarkedAt: existing?.bookmarkedAt,
            remoteSongCount: remoteSongCount
        )
    }
}
