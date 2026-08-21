//
//  SpeedDialEntry.swift
//  Trop
//
//  Created by 686udjie on 21/08/2026.
//

import Foundation
import GRDB

/// A song pinned to the homepage Speed Dial row.
struct SpeedDialEntry: Codable, Hashable, FetchableRecord, MutablePersistableRecord {
    var videoId: String
    var title: String
    var artist: String
    var album: String?
    var thumbnailUrl: String?
    var duration: Int
    var pinnedAt: Date

    static let databaseTableName = "speed_dial"

    enum CodingKeys: String, CodingKey {
        case videoId = "video_id"
        case title
        case artist
        case album
        case thumbnailUrl = "thumbnail_url"
        case duration
        case pinnedAt = "pinned_at"
    }

    init(song: SongItem) {
        self.videoId = song.videoId
        self.title = song.title
        self.artist = song.artists.map(\.name).joined(separator: ", ")
        self.album = song.album
        self.thumbnailUrl = song.thumbnailUrl
        self.duration = song.duration
        self.pinnedAt = Date()
    }

    /// Decodable init for GRDB.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        videoId = try c.decode(String.self, forKey: .videoId)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decode(String.self, forKey: .artist)
        album = try c.decodeIfPresent(String.self, forKey: .album)
        thumbnailUrl = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        duration = try c.decode(Int.self, forKey: .duration)
        pinnedAt = try c.decode(Date.self, forKey: .pinnedAt)
    }

    func toSongItem() -> SongItem {
        SongItem(
            videoId: videoId,
            title: title,
            artists: [YTArtist(name: artist, id: nil)],
            album: album,
            albumId: nil,
            duration: duration,
            thumbnailUrl: thumbnailUrl,
            isExplicit: false,
            playlistId: nil,
            likeStatus: nil
        )
    }
}
