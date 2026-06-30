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

    func searchSuggestions(input: String, client: YouTubeClient = .webRemix) async throws -> [String] {
        let json = try await innerTube.searchSuggestions(input: input, client: client)
        return parseSuggestions(from: json)
    }

    struct LocalSearchResults {
        var songs: [SongEntity] = []
        var artists: [ArtistEntity] = []
        var albums: [AlbumEntity] = []
        var playlists: [PlaylistEntity] = []
    }

    func localSearch(query: String) async throws -> LocalSearchResults {
        let pattern = "%\(query)%"
        async let songs = db.fetchAll(SongEntity.self, sql: "SELECT * FROM song WHERE title LIKE ? ORDER BY total_play_time DESC LIMIT 50", arguments: [pattern])
        async let artists = db.fetchAll(ArtistEntity.self, sql: "SELECT * FROM artist WHERE name LIKE ? LIMIT 20", arguments: [pattern])
        async let albums = db.fetchAll(AlbumEntity.self, sql: "SELECT * FROM album WHERE title LIKE ? LIMIT 20", arguments: [pattern])
        async let playlists = db.fetchAll(PlaylistEntity.self, sql: "SELECT * FROM playlist WHERE name LIKE ? LIMIT 20", arguments: [pattern])
        return try await LocalSearchResults(songs: songs, artists: artists, albums: albums, playlists: playlists)
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
                let entity = SongEntity(
                    id: song.videoId,
                    title: song.title,
                    duration: song.duration,
                    thumbnailUrl: song.thumbnailUrl ?? existing?.thumbnailUrl,
                    liked: existing?.liked ?? song.isLiked,
                    totalPlayTime: existing?.totalPlayTime ?? 0,
                    inLibrary: existing?.inLibrary,
                    libraryAddToken: existing?.libraryAddToken ?? song.libraryAddToken ?? "",
                    libraryRemoveToken: existing?.libraryRemoveToken ?? song.libraryRemoveToken ?? "",
                    isEpisode: existing?.isEpisode ?? false,
                    isUploaded: existing?.isUploaded ?? false,
                    isVideo: existing?.isVideo ?? false,
                    createDate: existing?.createDate ?? Date(),
                    modifyDate: Date()
                )
                try entity.save(db)
            }
        }
    }

    private func parseSuggestions(from json: [String: Any]) -> [String] {
        // Navigate to search suggestion contents
        guard let contents = json["contents"] as? [[String: Any]] else { return [] }
        var suggestions: [String] = []
        for item in contents {
            if let suggestion = item["searchSuggestionRenderer"] as? [String: Any],
               let runs = suggestion["suggestion"] as? [String: Any],
               let textRuns = runs["runs"] as? [[String: Any]],
               let first = textRuns.first,
               let text = first["text"] as? String {
                suggestions.append(text)
            }
        }
        return suggestions
    }

    private func extractRadioItems(from json: [String: Any]) -> [[String: Any]] {
        guard let contents = json["contents"] as? [String: Any],
              let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any] ?? contents["twoColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = singleColumn["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let sectionList = content["sectionListRenderer"] as? [String: Any],
              let sections = sectionList["contents"] as? [[String: Any]],
              let firstSection = sections.first,
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
