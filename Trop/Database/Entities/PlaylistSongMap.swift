//
// PlaylistSongMap.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

struct PlaylistSongMap: Codable, Hashable, FetchableRecord, PersistableRecord {
    var id: Int?
    var playlistId: String
    var songId: String
    var position: Int
    var setVideoId: String?

    static let databaseTableName = "playlist_song_map"

    enum CodingKeys: String, CodingKey {
        case id
        case playlistId = "playlist_id"
        case songId = "song_id"
        case position
        case setVideoId = "set_video_id"
    }
}
