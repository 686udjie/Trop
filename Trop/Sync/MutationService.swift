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

    private func emptySong(id: String, liked: Bool, addToken: String = "") -> SongEntity {
        SongEntity(
            id: id, title: "", artistName: nil, albumName: nil,
            duration: 0, thumbnailUrl: nil,
            liked: liked, totalPlayTime: 0, inLibrary: nil,
            libraryAddToken: addToken, libraryRemoveToken: "",
            isEpisode: false, isUploaded: false, isVideo: false,
            createDate: Date(), modifyDate: Date()
        )
    }

    private func enrichEmptySong(_ entity: SongEntity) async -> SongEntity {
        guard entity.title.isEmpty else { return entity }
        var enriched = entity
        if let metadata = try? await fetchSongMetadata(videoId: entity.id) {
            enriched.title = metadata.title
            enriched.artistName = metadata.artistName
            enriched.thumbnailUrl = metadata.thumbnailUrl
            enriched.duration = metadata.duration
            enriched.albumName = metadata.albumName
        }
        return enriched
    }

    private struct SongMetadata {
        let title: String
        let artistName: String?
        let thumbnailUrl: String?
        let duration: Int
        let albumName: String?
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

        let title = extractRunsText(primary["title"] as? [String: Any]) ?? ""

        let secondary = results["secondaryInfoRenderer"] as? [String: Any]
        let byline = secondary?["videoOwnerRenderer"] as? [String: Any]
        let bylineRuns = extractRawRuns(byline?["title"] as? [String: Any])
        let artistName = bylineRuns.first.map { $0["text"] as? String } ?? nil

        let thumbnailDict = primary["thumbnail"] as? [String: Any]
        let thumbnails = thumbnailDict?["thumbnails"] as? [[String: Any]]
        let thumbnailUrl = thumbnails?.last?["url"] as? String

        let lengthSeconds = primary["lengthSeconds"] as? String
        let duration = lengthSeconds.flatMap { Int($0) } ?? 0

        return SongMetadata(title: title, artistName: artistName, thumbnailUrl: thumbnailUrl, duration: duration, albumName: nil)
    }

    private func extractRunsText(_ dict: [String: Any]?) -> String? {
        guard let runs = dict?["runs"] as? [[String: Any]], let first = runs.first else { return nil }
        return first["text"] as? String
    }

    private func extractRawRuns(_ dict: [String: Any]?) -> [[String: Any]] {
        guard let runs = dict?["runs"] as? [[String: Any]] else { return [] }
        return runs
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
        do {
            _ = try await innerTube.like(videoId: videoId)
        } catch {
            entity.liked = false
            try? await db.save(entity)
            throw error
        }
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
        do {
            _ = try await innerTube.unlike(videoId: videoId)
        } catch {
            entity.liked = true
            try? await db.save(entity)
            throw error
        }
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
        guard !addToken.isEmpty else { return }
        do {
            _ = try await innerTube.feedback(tokens: [addToken])
        } catch {
            entity.inLibrary = nil
            try? await db.save(entity)
            throw error
        }
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
        do {
            _ = try await innerTube.feedback(tokens: [removeToken])
        } catch {
            if var existing = entity {
                existing.inLibrary = Date()
                existing.modifyDate = Date()
                try? await db.save(existing)
            }
            throw error
        }
    }

    func addToPlaylist(playlistId: String, songId: String, setVideoId: String? = nil) async throws {
        let entity = try? await db.fetchOne(PlaylistEntity.self, key: playlistId)
        let isLocal = entity?.browseId == nil

        var map = PlaylistSongMap(id: nil, playlistId: playlistId, songId: songId, position: 0, setVideoId: setVideoId)
        map = try await db.insert(map, onConflict: .ignore)

        if !isLocal {
            var actions: [[String: Any]] = [
                ["action": "ACTION_ADD_VIDEO", "addedVideoId": songId]
            ]
            if let setVideoId {
                actions[0]["setVideoId"] = setVideoId
            }
            do {
                _ = try await innerTube.editPlaylist(playlistId: playlistId, actions: actions)
            } catch {
                _ = try? await db.delete(map)
                throw error
            }
        }
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
        do {
            _ = try await innerTube.subscribe(channelId: channelId)
        } catch {
            if var existing = entity {
                existing.bookmarkedAt = nil
                existing.channelId = nil
                try? await db.save(existing)
            }
            throw error
        }
    }

    func unsubscribeArtist(channelId: String, artistId: String) async throws {
        var entity: ArtistEntity?
        if var existing = try await db.fetchOne(ArtistEntity.self, key: artistId) {
            existing.bookmarkedAt = nil
            entity = existing
            try? await db.save(existing)
        }
        do {
            _ = try await innerTube.unsubscribe(channelId: channelId)
        } catch {
            if var existing = entity {
                existing.bookmarkedAt = existing.bookmarkedAt ?? Date()
                try? await db.save(existing)
            }
            throw error
        }
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
