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
    private let innerTube = InnerTubeClient.tropShared
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
}
