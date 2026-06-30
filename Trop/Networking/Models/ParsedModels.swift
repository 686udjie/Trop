//
// ParsedModels.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation

struct ParsedSong {
    var videoId: String
    var title: String
    var artists: [String]
    var artistIds: [String]
    var album: String?
    var albumId: String?
    var duration: Int
    var thumbnailUrl: String?
    var isLiked: Bool
    var libraryAddToken: String?
    var libraryRemoveToken: String?
}

struct ParsedAlbum {
    var browseId: String
    var title: String
    var artist: String?
    var thumbnailUrl: String?
    var songCount: Int
    var duration: Int
    var playlistId: String?
}

struct ParsedArtist {
    var browseId: String
    var name: String
    var thumbnailUrl: String?
    var isSubscribed: Bool
}

struct ParsedPlaylist {
    var browseId: String
    var title: String
    var songCount: Int?
    var thumbnailUrl: String?
}
