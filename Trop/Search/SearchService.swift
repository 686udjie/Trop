//
// SearchService.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

actor SearchService {
    nonisolated static let shared = SearchService()
    private let innerTube = InnerTube.shared
    private let db = DatabaseService.shared
    private var searchTask: Task<[String: Any], Error>?

    func search(query: String, params: String? = nil, client: YouTubeClient = .webRemix) async throws -> [String: Any] {
        searchTask?.cancel()
        let task = Task { () -> [String: Any] in
            try await innerTube.search(query: query, params: params, client: client)
        }
        searchTask = task
        return try await task.value
    }

    struct LocalSearchResults {
        var songs: [SongEntity] = []
        var artists: [ArtistEntity] = []
        var albums: [AlbumEntity] = []
        var playlists: [PlaylistEntity] = []
    }

    func localSearch(query: String) async throws -> LocalSearchResults {
        let pattern = "%\(query)%"
        async let songs = db.fetchAll(
            SongEntity.self,
            sql: "SELECT * FROM song WHERE title LIKE ? OR artist_name LIKE ? ORDER BY total_play_time DESC LIMIT 50",
            arguments: [pattern, pattern]
        )
        async let artists = db.fetchAll(ArtistEntity.self, sql: "SELECT * FROM artist WHERE name LIKE ? LIMIT 20", arguments: [pattern])
        async let albums = db.fetchAll(AlbumEntity.self, sql: "SELECT * FROM album WHERE title LIKE ? LIMIT 20", arguments: [pattern])
        async let playlists = db.fetchAll(PlaylistEntity.self, sql: "SELECT * FROM playlist WHERE name LIKE ? LIMIT 20", arguments: [pattern])
        let results = try await LocalSearchResults(songs: songs, artists: artists, albums: albums, playlists: playlists)
        return results
    }

    func buildRadio(videoId: String, playlistId: String? = nil) async throws -> [[String: Any]] {
        let json = try await innerTube.next(videoId: videoId, playlistId: playlistId)
        return extractRadioItems(from: json)
    }

    // Cache search results in local DB
    func cacheSearchResults(_ songs: [ParsedSong]) async throws {
        try await db.write { db in
            for song in songs {
                let existing = try SongEntity.fetchOne(db, key: song.videoId)
                let entity = SongEntity.merging(
                    existing: existing,
                    id: song.videoId,
                    title: song.title,
                    artistName: song.artists.first,
                    albumName: song.album,
                    duration: song.duration,
                    thumbnailUrl: song.thumbnailUrl,
                    liked: song.isLiked,
                    libraryAddToken: song.libraryAddToken ?? "",
                    libraryRemoveToken: song.libraryRemoveToken ?? ""
                )
                try entity.save(db)
            }
        }
    }

    private func extractRadioItems(from json: [String: Any]) -> [[String: Any]] {
        guard let firstSection = BrowseLens.firstBrowseSection(json),
              let shelf = firstSection["musicShelfRenderer"] as? [String: Any],
              let items = shelf["contents"] as? [[String: Any]] else {
            // Try watching endpoint structure
            if let watching = json["contents"] as? [String: Any],
               let twoColumn = watching["twoColumnWatchNextResults"] as? [String: Any],
               let secondary = twoColumn["secondaryResults"] as? [String: Any],
               let secondaryResults = secondary["secondaryResults"] as? [String: Any],
               let results = secondaryResults["results"] as? [[String: Any]] {
                return results
            }
            return []
        }
        return items
    }
}
