//
// MutationService.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

actor MutationService {
    nonisolated static let shared = MutationService()
    private let innerTube = InnerTube.shared
    private let db = DatabaseService.shared

    /// Attempts a remote mutation, running `rollback` (best-effort) and
    /// rethrowing the original error on failure. Collapses the
    /// apply → remote → restore + rethrow skeleton shared by every
    /// optimistic mutation below.
    private func attemptingRemote(
        _ remote: () async throws -> Void,
        rollback: () async -> Void
    ) async throws {
        do {
            try await remote()
        } catch {
            await rollback()
            throw error
        }
    }

    private func emptySong(id: String, liked: Bool, addToken: String = "") -> SongEntity {
        SongEnrichment.skeleton(id: id, liked: liked, addToken: addToken)
    }

    private func enrichEmptySong(_ entity: SongEntity) async -> SongEntity {
        guard entity.title.isEmpty else { return entity }
        guard let metadata = try? await fetchSongMetadata(videoId: entity.id) else { return entity }
        return SongEnrichment.merging(entity, with: metadata)
    }

    private func fetchSongMetadata(videoId: String) async throws -> SongMetadata? {
        let json = try await innerTube.next(videoId: videoId)
        guard let contents = json["contents"] as? [String: Any],
              let singleColumn = contents["singleColumnMusicWatchNextResultsRenderer"] as? [String: Any],
              let tabbed = singleColumn["tabbedRenderer"] as? [String: Any],
              let watchNext = tabbed["watchNextTabbedResultsRenderer"] as? [String: Any],
              let tabs = watchNext["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let results = content["results"] as? [String: Any],
              let primary = results["primaryInfoRenderer"] as? [String: Any] else {
            return nil
        }

        let title = InnerTubeJSON.runsText(primary["title"] as? [String: Any]) ?? ""

        let secondary = results["secondaryInfoRenderer"] as? [String: Any]
        let byline = secondary?["videoOwnerRenderer"] as? [String: Any]
        let bylineRuns = InnerTubeJSON.rawRuns(byline?["title"] as? [String: Any])
        let artistName = bylineRuns.first.map { $0["text"] as? String } ?? nil

        let thumbnailDict = primary["thumbnail"] as? [String: Any]
        let thumbnails = thumbnailDict?["thumbnails"] as? [[String: Any]]
        let thumbnailUrl = thumbnails?.last?["url"] as? String

        let lengthSeconds = primary["lengthSeconds"] as? String
        let duration = lengthSeconds.flatMap { Int($0) } ?? 0

        return SongMetadata(title: title, artistName: artistName, thumbnailUrl: thumbnailUrl, duration: duration, albumName: nil)
    }

    func likeSong(videoId: String) async throws {
        var entity: SongEntity
        if let existing = try await db.fetchOne(SongEntity.self, key: videoId) {
            entity = existing
        } else {
            let skeleton = emptySong(id: videoId, liked: false)
            entity = await enrichEmptySong(skeleton)
        }
        entity.liked = true
        entity.modifyDate = Date()
        try await db.save(entity)
        let applied = entity
        try await attemptingRemote(
            { _ = try await innerTube.like(videoId: videoId) },
            rollback: {
                var restored = applied
                restored.liked = false
                try? await db.save(restored)
            }
        )
    }

    func unlikeSong(videoId: String) async throws {
        var entity: SongEntity
        if let existing = try await db.fetchOne(SongEntity.self, key: videoId) {
            entity = existing
        } else {
            let skeleton = emptySong(id: videoId, liked: true)
            entity = await enrichEmptySong(skeleton)
        }
        entity.liked = false
        entity.modifyDate = Date()
        try? await db.save(entity)
        let applied = entity
        try await attemptingRemote(
            { _ = try await innerTube.unlike(videoId: videoId) },
            rollback: {
                var restored = applied
                restored.liked = true
                try? await db.save(restored)
            }
        )
    }

    func addToLibrary(videoId: String, addToken: String) async throws {
        var entity: SongEntity
        if let existing = try await db.fetchOne(SongEntity.self, key: videoId) {
            entity = existing
        } else {
            let skeleton = emptySong(id: videoId, liked: false, addToken: addToken)
            entity = await enrichEmptySong(skeleton)
        }
        entity.inLibrary = entity.inLibrary ?? Date()
        entity.modifyDate = Date()
        try? await db.save(entity)
        let applied = entity
        guard !addToken.isEmpty else { return }
        try await attemptingRemote(
            { _ = try await innerTube.feedback(tokens: [addToken]) },
            rollback: {
                var restored = applied
                restored.inLibrary = nil
                try? await db.save(restored)
            }
        )
    }

    func removeFromLibrary(videoId: String, removeToken: String) async throws {
        var entity: SongEntity?
        if var existing = try await db.fetchOne(SongEntity.self, key: videoId) {
            existing.inLibrary = nil
            existing.modifyDate = Date()
            entity = existing
            try? await db.save(existing)
        }
        guard !removeToken.isEmpty else { return }
        let applied = entity
        try await attemptingRemote(
            { _ = try await innerTube.feedback(tokens: [removeToken]) },
            rollback: {
                if var restored = applied {
                    restored.inLibrary = Date()
                    restored.modifyDate = Date()
                    try? await db.save(restored)
                }
            }
        )
    }

    func addToPlaylist(playlistId: String, songId: String, setVideoId: String? = nil) async throws {
        let entity = try? await db.fetchOne(PlaylistEntity.self, key: playlistId)
        let isLocal = entity?.browseId == nil

        var map = PlaylistSongMap(id: nil, playlistId: playlistId, songId: songId, position: 0, setVideoId: setVideoId)
        map = try await db.insert(map, onConflict: .ignore)
        guard !isLocal else { return }

        var actions: [[String: Any]] = [
            ["action": "ACTION_ADD_VIDEO", "addedVideoId": songId]
        ]
        if let setVideoId {
            actions[0]["setVideoId"] = setVideoId
        }
        let inserted = map
        try await attemptingRemote(
            { _ = try await innerTube.editPlaylist(playlistId: playlistId, actions: actions) },
            rollback: { _ = try? await db.delete(inserted) }
        )
    }

    func removeFromPlaylist(playlistId: String, songId: String, setVideoId: String) async throws {
        let entity = try? await db.fetchOne(PlaylistEntity.self, key: playlistId)
        let isLocal = entity?.browseId == nil

        if !isLocal {
            let actions: [[String: Any]] = [
                ["action": "ACTION_REMOVE_VIDEO", "setVideoId": setVideoId]
            ]
            do {
                _ = try await innerTube.editPlaylist(playlistId: playlistId, actions: actions)
            } catch {
                throw error
            }
        }

        try await db.write { db in
            try db.execute(sql: "DELETE FROM playlist_song_map WHERE playlist_id = ? AND song_id = ?", arguments: [playlistId, songId])
        }
    }

    func createPlaylist(title: String, description: String? = nil) async throws -> String {
        let json = try await innerTube.createPlaylist(title: title, description: description)
        guard let playlistId = extractPlaylistId(from: json) else {
            throw MutationError.playlistCreationFailed
        }
        var entity = PlaylistEntity(
            id: playlistId,
            browseId: "VL\(playlistId)",
            name: title,
            isEditable: true,
            bookmarkedAt: Date(),
            remoteSongCount: 0
        )
        entity = try await db.insertOrReplace(entity)
        return playlistId
    }

    func deletePlaylist(playlistId: String) async throws {
        let entity = try? await db.fetchOne(PlaylistEntity.self, key: playlistId)
        let isLocal = entity?.browseId == nil

        if !isLocal {
            do {
                _ = try await innerTube.deletePlaylist(playlistId: playlistId)
            } catch {
                throw error
            }
        }

        try await db.write { db in
            try db.execute(sql: "DELETE FROM playlist_song_map WHERE playlist_id = ?", arguments: [playlistId])
            try db.execute(sql: "DELETE FROM playlist WHERE id = ?", arguments: [playlistId])
        }
    }

    func renamePlaylist(playlistId: String, newName: String) async throws {
        guard var entity = try? await db.fetchOne(PlaylistEntity.self, key: playlistId) else {
            throw NSError(domain: "MutationService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Playlist not found"])
        }

        let isLocal = entity.browseId == nil

        if !isLocal {
            let actions: [[String: Any]] = [
                ["action": "ACTION_SET_PLAYLIST_NAME", "name": newName]
            ]
            _ = try await innerTube.editPlaylist(playlistId: playlistId, actions: actions)
        }

        entity.name = newName
        try await db.save(entity)
    }

    func subscribeArtist(channelId: String, artistId: String) async throws {
        var entity: ArtistEntity?
        if var existing = try await db.fetchOne(ArtistEntity.self, key: artistId) {
            existing.bookmarkedAt = Date()
            existing.channelId = channelId
            entity = existing
            try? await db.save(existing)
        }
        let applied = entity
        try await attemptingRemote(
            { _ = try await innerTube.subscribe(channelId: channelId) },
            rollback: {
                if var restored = applied {
                    restored.bookmarkedAt = nil
                    restored.channelId = nil
                    try? await db.save(restored)
                }
            }
        )
    }

    func unsubscribeArtist(channelId: String, artistId: String) async throws {
        var entity: ArtistEntity?
        if var existing = try await db.fetchOne(ArtistEntity.self, key: artistId) {
            existing.bookmarkedAt = nil
            entity = existing
            try? await db.save(existing)
        }
        let applied = entity
        try await attemptingRemote(
            { _ = try await innerTube.unsubscribe(channelId: channelId) },
            rollback: {
                if var restored = applied {
                    restored.bookmarkedAt = restored.bookmarkedAt ?? Date()
                    try? await db.save(restored)
                }
            }
        )
    }

    private func extractPlaylistId(from json: [String: Any]) -> String? {
        if let playlistId = json["playlistId"] as? String { return playlistId }
        if let response = json["response"] as? [String: Any],
           let playlistId = response["playlistId"] as? String { return playlistId }
        return nil
    }
}

enum MutationError: Error, LocalizedError {
    case playlistCreationFailed
    var errorDescription: String? { "Failed to create playlist" }
}
