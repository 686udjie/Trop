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
        let browseId = "VL\(playlistId)"
        let allItems: [[String: Any]] = try await innerTube.paginate(
            browseId: browseId,
            parse: { self.extractPlaylistItems(from: $0) ?? [] },
            continuation: { self.extractPlaylistContinuation(from: $0) }
        )

        let snapshot = allItems
        try await db.write { db in
            let existing = try PlaylistEntity.fetchOne(db, key: playlistId)
            let entity = PlaylistEntity.merging(
                existing: existing,
                id: playlistId,
                browseId: browseId,
                name: "Playlist",
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
                    let entity = SongEntity.merging(
                        existing: existing,
                        id: videoId,
                        title: songItem.title,
                        artistName: songItem.artists.first?.name,
                        albumName: songItem.album,
                        duration: songItem.duration,
                        thumbnailUrl: songItem.thumbnailUrl
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
        if let firstSection = BrowseLens.firstBrowseSection(json),
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
        if let firstSection = BrowseLens.firstBrowseSection(json),
           let shelf = (firstSection["musicPlaylistShelfRenderer"] as? [String: Any])
            ?? (firstSection["musicShelfRenderer"] as? [String: Any]),
           let token = BrowseLens.continuationToken(in: shelf) {
            return token
        }
        if let continuationContents = json["continuationContents"] as? [String: Any],
           let shelf = (continuationContents["musicPlaylistShelfContinuation"] as? [String: Any])
            ?? (continuationContents["musicShelfContinuation"] as? [String: Any]),
           let token = BrowseLens.continuationToken(in: shelf) {
            return token
        }
        return nil
    }

    private func extractAlbumPlaylistId(from json: [String: Any]) -> String? {
        guard let microformat = json["microformat"] as? [String: Any] ?? (json["header"] as? [String: Any]) else { return nil }
        // Try various paths to find the playlistId in the album microformat
        let renderers = [microformat["musicMicroformatRenderer"], microformat["microformatDataRenderer"]]
            .compactMap { ($0 as? [String: Any])?["urlCanonical"] as? String }
        for urlString in renderers {
            guard let url = URL(string: urlString),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
            // Canonical album URLs look like https://music.youtube.com/playlist?list=OLAK5uy_...
            if let list = components.queryItems?.first(where: { $0.name == "list" })?.value,
               !list.isEmpty, list != "playlist" {
                return list
            }
            // Fallback: a path like /playlist/OLAK5uy_... — but never the bare "playlist" segment
            if let last = url.pathComponents.last, last != "playlist", !last.isEmpty {
                return last
            }
        }
        return nil
    }
}

enum PlaylistError: Error, LocalizedError {
    case noPlaylistId
    var errorDescription: String? { "Could not extract playlist ID from album page" }
}
