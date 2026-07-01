//
// SongEntity.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

struct SongEntity: Codable, Hashable, FetchableRecord, PersistableRecord {
    var id: String
    var title: String
    var artistName: String?
    var albumName: String?
    var duration: Int
    var thumbnailUrl: String?
    var liked: Bool
    var totalPlayTime: Int64
    var inLibrary: Date?
    var libraryAddToken: String
    var libraryRemoveToken: String
    var isEpisode: Bool
    var isUploaded: Bool
    var isVideo: Bool
    var createDate: Date
    var modifyDate: Date

    static let databaseTableName = "song"

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case artistName = "artist_name"
        case albumName = "album_name"
        case duration
        case thumbnailUrl = "thumbnail_url"
        case liked
        case totalPlayTime = "total_play_time"
        case inLibrary = "in_library"
        case libraryAddToken = "library_add_token"
        case libraryRemoveToken = "library_remove_token"
        case isEpisode = "is_episode"
        case isUploaded = "is_uploaded"
        case isVideo = "is_video"
        case createDate = "create_date"
        case modifyDate = "modify_date"
    }
}
