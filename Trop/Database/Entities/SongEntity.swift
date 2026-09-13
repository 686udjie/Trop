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

// swiftlint:disable function_parameter_count
extension SongEntity {
    /// Merges freshly fetched metadata over the stored row, preserving user
    /// state (liked, play time, library flags, tokens, original createDate).
    /// Unknown incoming values (empty title parts, zero duration, nil artwork)
    /// fall back to the stored row instead of wiping it.
    static func merging(
        existing: SongEntity?,
        id: String,
        title: String,
        artistName: String?,
        albumName: String?,
        duration: Int,
        thumbnailUrl: String?,
        liked: Bool = false,
        libraryAddToken: String = "",
        libraryRemoveToken: String = "",
        isEpisode: Bool = false,
        isUploaded: Bool = false,
        isVideo: Bool = false
    ) -> SongEntity {
        SongEntity(
            id: id,
            title: title,
            artistName: existing?.artistName ?? artistName,
            albumName: existing?.albumName ?? albumName,
            duration: duration > 0 ? duration : existing?.duration ?? 0,
            thumbnailUrl: thumbnailUrl ?? existing?.thumbnailUrl,
            liked: existing?.liked ?? liked,
            totalPlayTime: existing?.totalPlayTime ?? 0,
            inLibrary: existing?.inLibrary,
            libraryAddToken: existing?.libraryAddToken ?? libraryAddToken,
            libraryRemoveToken: existing?.libraryRemoveToken ?? libraryRemoveToken,
            isEpisode: existing?.isEpisode ?? isEpisode,
            isUploaded: existing?.isUploaded ?? isUploaded,
            isVideo: existing?.isVideo ?? isVideo,
            createDate: existing?.createDate ?? Date(),
            modifyDate: Date()
        )
    }
}
// swiftlint:enable function_parameter_count
