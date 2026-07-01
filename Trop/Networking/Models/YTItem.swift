//
//  YTItem.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import Foundation

struct YTArtist {
    var name: String
    var id: String?
}

enum YTItem {
    case song(SongItem)
    case album(AlbumItem)
    case artist(ArtistItem)
    case playlist(PlaylistItem)
    case podcast(PodcastItem)
    case episode(EpisodeItem)

    var id: String {
        switch self {
        case .song(let s): return s.videoId
        case .album(let a): return a.browseId
        case .artist(let a): return a.browseId
        case .playlist(let p): return p.id
        case .podcast(let p): return p.browseId
        case .episode(let e): return e.videoId
        }
    }

    var title: String {
        switch self {
        case .song(let s): return s.title
        case .album(let a): return a.title
        case .artist(let a): return a.name
        case .playlist(let p): return p.title
        case .podcast(let p): return p.title
        case .episode(let e): return e.title
        }
    }

    var thumbnailUrl: String? {
        switch self {
        case .song(let s): return s.thumbnailUrl
        case .album(let a): return a.thumbnailUrl
        case .artist(let a): return a.thumbnailUrl
        case .playlist(let p): return p.thumbnailUrl
        case .podcast(let p): return p.thumbnailUrl
        case .episode(let e): return e.thumbnailUrl
        }
    }

    var subtitle: String {
        switch self {
        case .song(let s): return s.artists.map(\.name).joined(separator: ", ")
        case .album(let a): return a.artists.map(\.name).joined(separator: ", ")
        case .artist: return "Artist"
        case .playlist(let p): return p.author ?? "Playlist"
        case .podcast(let p): return p.author ?? "Podcast"
        case .episode(let e): return e.artists.map(\.name).joined(separator: ", ")
        }
    }

    var videoId: String? {
        switch self {
        case .song(let s): return s.videoId
        case .episode(let e): return e.videoId
        default: return nil
        }
    }
}

struct SongItem {
    var videoId: String
    var title: String
    var artists: [YTArtist]
    var album: String?
    var albumId: String?
    var duration: Int
    var thumbnailUrl: String?
    var isExplicit: Bool
    var playlistId: String?
    var likeStatus: String?

    static func from(_ renderer: [String: Any]) -> SongItem? {
        guard let videoId = extractVideoId(renderer) else { return nil }
        let title = extractRunsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let subtitleRuns = extractRunsTextArray(renderer["subtitle"] as? [String: Any])
        let thumbnailUrl = extractTwoRowThumbnail(renderer)
        let playlistId = extractPlaylistId(renderer)

        return SongItem(
            videoId: videoId,
            title: title,
            artists: [],
            album: subtitleRuns.first,
            duration: 0,
            thumbnailUrl: thumbnailUrl,
            isExplicit: false,
            playlistId: playlistId
        )
    }
}

struct AlbumItem {
    var browseId: String
    var title: String
    var artists: [YTArtist]
    var year: Int?
    var thumbnailUrl: String?
    var playlistId: String?
    var isExplicit: Bool

    static func from(_ renderer: [String: Any]) -> AlbumItem? {
        guard let browseId = extractTwoRowBrowseId(renderer) else { return nil }
        let title = extractRunsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let thumbnailUrl = extractTwoRowThumbnail(renderer)
        return AlbumItem(
            browseId: browseId,
            title: title,
            artists: [],
            thumbnailUrl: thumbnailUrl,
            playlistId: extractPlaylistId(renderer),
            isExplicit: false
        )
    }
}

struct ArtistItem {
    var browseId: String
    var name: String
    var thumbnailUrl: String?
    var isSubscribed: Bool

    static func from(_ renderer: [String: Any]) -> ArtistItem? {
        guard let browseId = extractTwoRowBrowseId(renderer) else { return nil }
        let name = extractRunsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let thumbnailUrl = extractTwoRowThumbnail(renderer)
        return ArtistItem(browseId: browseId, name: name, thumbnailUrl: thumbnailUrl, isSubscribed: false)
    }
}

struct PlaylistItem {
    var id: String
    var title: String
    var author: String?
    var thumbnailUrl: String?
    var songCount: Int?

    static func from(_ renderer: [String: Any]) -> PlaylistItem? {
        guard let browseId = extractTwoRowBrowseId(renderer) else { return nil }
        let title = extractRunsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let thumbnailUrl = extractTwoRowThumbnail(renderer)
        let subtitleRuns = extractRunsTextArray(renderer["subtitle"] as? [String: Any])
        return PlaylistItem(
            id: browseId,
            title: title,
            author: subtitleRuns.first,
            thumbnailUrl: thumbnailUrl
        )
    }
}

struct PodcastItem {
    var browseId: String
    var title: String
    var author: String?
    var thumbnailUrl: String?

    static func from(_ renderer: [String: Any]) -> PodcastItem? {
        guard let browseId = extractTwoRowBrowseId(renderer) else { return nil }
        let title = extractRunsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let thumbnailUrl = extractTwoRowThumbnail(renderer)
        return PodcastItem(browseId: browseId, title: title, thumbnailUrl: thumbnailUrl)
    }
}

struct EpisodeItem {
    var videoId: String
    var title: String
    var artists: [YTArtist]
    var duration: Int
    var thumbnailUrl: String?
    var publishDate: String?

    static func from(_ renderer: [String: Any]) -> EpisodeItem? {
        guard let videoId = extractVideoId(renderer) else { return nil }
        let title = extractRunsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let thumbnailUrl = extractTwoRowThumbnail(renderer)
        return EpisodeItem(videoId: videoId, title: title, artists: [], duration: 0, thumbnailUrl: thumbnailUrl)
    }
}

// MARK: - Convenience Init from Entities

extension SongItem {
    init(entity: SongEntity) {
        self.videoId = entity.id
        self.title = entity.title
        self.artists = entity.artistName.map { [YTArtist(name: $0)] } ?? []
        self.album = entity.albumName
        self.albumId = nil
        self.duration = entity.duration
        self.thumbnailUrl = entity.thumbnailUrl
        self.isExplicit = false
        self.playlistId = nil
        self.likeStatus = nil
    }
}

extension AlbumItem {
    init(entity: AlbumEntity) {
        self.browseId = entity.id
        self.title = entity.title
        self.artists = []
        self.year = nil
        self.thumbnailUrl = entity.thumbnailUrl
        self.playlistId = entity.playlistId
        self.isExplicit = false
    }
}

extension ArtistItem {
    init(entity: ArtistEntity) {
        self.browseId = entity.id
        self.name = entity.name
        self.thumbnailUrl = entity.thumbnailUrl
        self.isSubscribed = entity.bookmarkedAt != nil
    }
}

extension PlaylistItem {
    init(entity: PlaylistEntity) {
        self.id = entity.id
        self.title = entity.name
        self.author = nil
        self.thumbnailUrl = nil
        self.songCount = entity.remoteSongCount
    }
}

// MARK: - Extract Helpers

private func extractVideoId(_ renderer: [String: Any]) -> String? {
    if let videoId = renderer["videoId"] as? String { return videoId }
    guard let nav = renderer["navigationEndpoint"] as? [String: Any],
          let watch = nav["watchEndpoint"] as? [String: Any],
          let videoId = watch["videoId"] as? String else { return nil }
    return videoId
}

private func extractTwoRowBrowseId(_ renderer: [String: Any]) -> String? {
    guard let nav = renderer["navigationEndpoint"] as? [String: Any],
          let browse = nav["browseEndpoint"] as? [String: Any],
          let bid = browse["browseId"] as? String else { return nil }
    return bid
}

private func extractPlaylistId(_ renderer: [String: Any]) -> String? {
    guard let nav = renderer["navigationEndpoint"] as? [String: Any],
          let watch = nav["watchEndpoint"] as? [String: Any],
          let pid = watch["playlistId"] as? String else { return nil }
    return pid
}

private func extractTwoRowThumbnail(_ renderer: [String: Any]) -> String? {
    if let thumb = extractThumbnailFrom(renderer["thumbnail"] as? [String: Any]) {
        return thumb
    }
    if let thumbRenderer = renderer["thumbnailRenderer"] as? [String: Any],
       let musicThumb = thumbRenderer["musicThumbnailRenderer"] as? [String: Any] {
        return extractThumbnailFrom(musicThumb)
    }
    return nil
}

private func extractThumbnailFrom(_ dict: [String: Any]?) -> String? {
    guard let thumb = dict?["thumbnail"] as? [String: Any],
          let thumbnails = thumb["thumbnails"] as? [[String: Any]],
          let last = thumbnails.last,
          let url = last["url"] as? String else { return nil }
    return url
}

private func extractRunsText(_ dict: [String: Any]?) -> String? {
    guard let runs = dict?["runs"] as? [[String: Any]], let first = runs.first else { return nil }
    return first["text"] as? String
}

private func extractRunsTextArray(_ dict: [String: Any]?) -> [String] {
    guard let runs = dict?["runs"] as? [[String: Any]] else { return [] }
    return runs.compactMap { $0["text"] as? String }
        .filter { $0 != " • " && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
}
