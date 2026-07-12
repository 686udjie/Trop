//
// PlaylistDetailService.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

actor PlaylistDetailService {
    nonisolated static let shared = PlaylistDetailService()
    private let innerTube = InnerTube.shared
    private let db = DatabaseService.shared

    func fetchPlaylist(playlistId: String) async throws -> Int {
        var allItems: [[String: Any]] = []
        var continuation: String?
        let browseId = "VL\(playlistId)"
        repeat {
            let json = try await innerTube.browse(browseId: browseId, continuation: continuation)
            if let items = extractPlaylistItems(from: json) {
                allItems.append(contentsOf: items)
            }
            continuation = extractPlaylistContinuation(from: json)
        } while continuation != nil

        let snapshot = allItems
        try await db.write { db in
            let existing = try PlaylistEntity.fetchOne(db, key: playlistId)
            let entity = PlaylistEntity(
                id: playlistId,
                browseId: browseId,
                name: existing?.name ?? "Playlist",
                isEditable: existing?.isEditable ?? false,
                bookmarkedAt: existing?.bookmarkedAt,
                remoteSongCount: snapshot.count
            )
            try entity.save(db)

            // Clear existing song mappings and re-insert
            try db.execute(sql: "DELETE FROM playlist_song_map WHERE playlist_id = ?", arguments: [playlistId])
            for (index, rawItem) in snapshot.enumerated() {
                guard let renderer = rawItem["musicResponsiveListItemRenderer"] as? [String: Any],
                      let nav = renderer["navigationEndpoint"] as? [String: Any],
                      let watch = nav["watchEndpoint"] as? [String: Any],
                      let videoId = watch["videoId"] as? String else { continue }
                let setVideoId = watch["playlistSetVideoId"] as? String

                if let songItem = SongItem.from(renderer) {
                    let existing = try SongEntity.fetchOne(db, key: videoId)
                    let entity = SongEntity(
                        id: videoId,
                        title: songItem.title,
                        artistName: existing?.artistName ?? songItem.artists.first?.name,
                        albumName: existing?.albumName ?? songItem.album,
                        duration: songItem.duration > 0 ? songItem.duration : existing?.duration ?? 0,
                        thumbnailUrl: songItem.thumbnailUrl ?? existing?.thumbnailUrl,
                        liked: existing?.liked ?? false,
                        totalPlayTime: existing?.totalPlayTime ?? 0,
                        inLibrary: existing?.inLibrary,
                        libraryAddToken: existing?.libraryAddToken ?? "",
                        libraryRemoveToken: existing?.libraryRemoveToken ?? "",
                        isEpisode: existing?.isEpisode ?? false,
                        isUploaded: existing?.isUploaded ?? false,
                        isVideo: existing?.isVideo ?? false,
                        createDate: existing?.createDate ?? Date(),
                        modifyDate: Date()
                    )
                    try entity.save(db)
                }

                let map = PlaylistSongMap(
                    id: nil,
                    playlistId: playlistId,
                    songId: videoId,
                    position: index,
                    setVideoId: setVideoId
                )
                try map.insert(db, onConflict: .ignore)
            }
        }
        return allItems.count
    }

    func fetchAlbum(albumBrowseId: String) async throws -> Int {
        let json = try await innerTube.browse(browseId: albumBrowseId)
        // Extract playlistId from the album page microformat
        guard let playlistId = extractAlbumPlaylistId(from: json) else {
            throw PlaylistError.noPlaylistId
        }
        return try await fetchPlaylist(playlistId: playlistId)
    }

    private func extractPlaylistItems(from json: [String: Any]) -> [[String: Any]]? {
        if let contents = json["contents"] as? [String: Any],
           let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumn["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let content = tabRenderer["content"] as? [String: Any],
           let sectionList = content["sectionListRenderer"] as? [String: Any],
           let sections = sectionList["contents"] as? [[String: Any]],
           let firstSection = sections.first,
           let shelf = (firstSection["musicPlaylistShelfRenderer"] as? [String: Any])
            ?? (firstSection["musicShelfRenderer"] as? [String: Any]),
           let items = shelf["contents"] as? [[String: Any]] {
            return items
        }
        if let continuationContents = json["continuationContents"] as? [String: Any],
           let shelf = (continuationContents["musicPlaylistShelfContinuation"] as? [String: Any])
            ?? (continuationContents["musicShelfContinuation"] as? [String: Any]),
           let items = shelf["contents"] as? [[String: Any]] {
            return items
        }
        return nil
    }

    private func extractPlaylistContinuation(from json: [String: Any]) -> String? {
        let continuations: [[String: Any]]?
        if let contents = json["contents"] as? [String: Any],
           let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumn["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let content = tabRenderer["content"] as? [String: Any],
           let sectionList = content["sectionListRenderer"] as? [String: Any],
           let sections = sectionList["contents"] as? [[String: Any]],
           let firstSection = sections.first,
           let shelf = (firstSection["musicPlaylistShelfRenderer"] as? [String: Any])
            ?? (firstSection["musicShelfRenderer"] as? [String: Any]) {
            continuations = shelf["continuations"] as? [[String: Any]]
        } else if let continuationContents = json["continuationContents"] as? [String: Any],
                  let shelf = (continuationContents["musicPlaylistShelfContinuation"] as? [String: Any])
                   ?? (continuationContents["musicShelfContinuation"] as? [String: Any]) {
            continuations = shelf["continuations"] as? [[String: Any]]
        } else {
            continuations = nil
        }
        guard let first = continuations?.first,
              let next = first["nextContinuationData"] as? [String: Any],
              let token = next["continuation"] as? String else { return nil }
        return token
    }

    private func extractAlbumPlaylistId(from json: [String: Any]) -> String? {
        guard let microformat = json["microformat"] as? [String: Any] ?? (json["header"] as? [String: Any]).flatMap({ $0 }) else { return nil }
        // Try various paths to find the playlistId in the album microformat
        if let renderer = microformat["musicMicroformatRenderer"] as? [String: Any],
           let url = renderer["urlCanonical"] as? String,
           url.contains("playlist") {
            return URL(string: url)?.pathComponents.last
        }
        // Fallback: check microformatDataRenderer
        if let dataRenderer = microformat["microformatDataRenderer"] as? [String: Any],
           let url = dataRenderer["urlCanonical"] as? String,
           url.contains("playlist") {
            return URL(string: url)?.pathComponents.last
        }
        return nil
    }
}

enum PlaylistError: Error, LocalizedError {
    case noPlaylistId
    var errorDescription: String? { "Could not extract playlist ID from album page" }
}
