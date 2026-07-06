//
//  DetailModels.swift
//  Trop
//
//  Created by 686udjie on 03/07/2026.
//

import Foundation

/// Parsed detail data for an album page.
struct AlbumDetailInfo {
    var title: String
    var artists: [YTArtist]
    var year: Int?
    var songCount: Int
    var duration: Int
    var thumbnailUrl: String?
    var playlistId: String?
    var browseId: String
    var songs: [SongItem]
}

/// Parsed detail data for an artist page.
struct ArtistDetailInfo {
    var name: String
    var thumbnailUrl: String?
    var subscriberCountText: String?
    var descriptionText: String?
    var isSubscribed: Bool
    var browseId: String
    var songs: [SongItem]
    var albums: [AlbumItem]
}

/// Parsed detail data for a playlist page.
struct PlaylistDetailInfo {
    var title: String
    var authorName: String?
    var authorBrowseId: String?
    var authorAvatarUrl: String?
    var descriptionText: String?
    var songCount: Int
    var duration: Int
    var thumbnailUrl: String?
    var playlistId: String
    var songs: [SongItem]
}

/// Parsed detail data for a podcast page.
struct PodcastDetailInfo {
    var title: String
    var author: String?
    var descriptionText: String?
    var thumbnailUrl: String?
    var browseId: String
    var episodes: [EpisodeItem]
}
