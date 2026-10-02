//
// LibrarySyncService.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

actor LibrarySyncService {
    nonisolated static let shared = LibrarySyncService()
    private let innerTube = InnerTube.shared
    private let db = DatabaseService.shared

    func syncAll() async -> LibrarySyncResult {
        var result = LibrarySyncResult()
        let settings = SettingsStore.shared
        if settings.syncArtists {
            do { result.artistIds = try await syncSubscribedArtists() } catch { Log.sync.error("syncSubscribedArtists error: \(error)") }
        }
        if settings.syncPlaylists {
            do { result.playlistIds = try await syncLikedPlaylists() } catch { Log.sync.error("syncLikedPlaylists error: \(error)") }
        }
        if settings.syncAlbums {
            do { result.albumIds = try await syncSavedAlbums() } catch { Log.sync.error("syncSavedAlbums error: \(error)") }
        }
        if settings.syncPodcasts {
            do { result.podcastIds = try await syncSubscribedPodcasts() } catch { Log.sync.error("syncSubscribedPodcasts error: \(error)") }
        }
        if settings.syncSongs {
            do { result.songIds = try await syncLikedSongs() } catch { Log.sync.error("syncLikedSongs error: \(error)") }
        }
        await LikeStore.shared.refresh()
        return result
    }
}

// MARK: Section sync

extension LibrarySyncService {
    func syncSubscribedArtists() async throws -> Set<String> {
        let items = try await fetchAllPages(browseId: "FEmusic_library_corpus_artists") { json in
            LibraryBrowseParser.parseArtists(from: json)
        }
        let remoteIds = Set(items.map(\.browseId))
        try await db.write { db in
            for item in items {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO artist (id, name, thumbnail_url, bookmarked_at, is_podcast_channel, channel_id)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [item.browseId, item.name, item.thumbnailUrl,
                                     Date(), false, item.channelId])
            }
            // Unset bookmarked_at for artists no longer subscribed remotely
            if !remoteIds.isEmpty {
                let placeholders = DatabaseService.placeholders(count: remoteIds.count)
                try db.execute(
                    sql: "UPDATE artist SET bookmarked_at = NULL WHERE bookmarked_at IS NOT NULL AND id NOT IN (\(placeholders))",
                    arguments: StatementArguments(Array(remoteIds))
                )
            }
        }
        return remoteIds
    }

    func syncLikedPlaylists() async throws -> Set<String> {
        // YTM's Liked Music pseudo-playlist must never materialize as a
        // library row — its members merge into Liked Songs via syncLikedSongs.
        let likedMusicIds: Set<String> = ["LM", "VLLM"]
        let items = try await fetchAllPages(browseId: "FEmusic_liked_playlists") { json in
            LibraryBrowseParser.parsePlaylists(from: json).filter { !likedMusicIds.contains($0.browseId) }
        }
        let remoteIds = Set(items.map(\.browseId))
        try await db.write { db in
            for item in items {
                let existing = try PlaylistEntity.fetchOne(db, key: item.browseId)
                let entity = PlaylistEntity(
                    id: item.browseId,
                    browseId: item.browseId,
                    name: item.title,
                    thumbnailUrl: item.thumbnailUrl ?? existing?.thumbnailUrl,
                    isEditable: existing?.isEditable ?? false,
                    bookmarkedAt: existing?.bookmarkedAt ?? Date(),
                    remoteSongCount: item.songCount ?? existing?.remoteSongCount,
                    isAutoSync: true
                )
                try entity.save(db)
            }
            // Remove playlists unliked remotely — only playlists that were
            // created by sync (is_auto_sync = 1). Locally-created playlists
            // also carry a browseId but must never be deleted by a sync sweep.
            if !remoteIds.isEmpty {
                try db.execute(sql: """
                    DELETE FROM playlist_song_map WHERE playlist_id IN (
                        SELECT id FROM playlist WHERE is_auto_sync = 1 AND browse_id IS NOT NULL
                        AND browse_id NOT IN (\(DatabaseService.placeholders(count: remoteIds.count)))
                    )
                    """, arguments: StatementArguments(Array(remoteIds)))
                try db.execute(sql: """
                    DELETE FROM playlist WHERE is_auto_sync = 1 AND browse_id IS NOT NULL
                    AND browse_id NOT IN (\(DatabaseService.placeholders(count: remoteIds.count)))
                    """, arguments: StatementArguments(Array(remoteIds)))
            }
        }
        return remoteIds
    }

    func syncSavedAlbums() async throws -> Set<String> {
        let items = try await fetchAllPages(browseId: "FEmusic_liked_albums") { json in
            LibraryBrowseParser.parseAlbums(from: json)
        }
        let remoteIds = Set(items.map(\.browseId))
        try await db.write { db in
            for item in items {
                let existing = try AlbumEntity.fetchOne(db, key: item.browseId)
                let entity = AlbumEntity(
                    id: item.browseId,
                    title: item.title,
                    playlistId: item.playlistId ?? existing?.playlistId,
                    thumbnailUrl: item.thumbnailUrl ?? existing?.thumbnailUrl,
                    songCount: item.songCount != 0 ? item.songCount : (existing?.songCount ?? 0),
                    duration: item.duration != 0 ? item.duration : (existing?.duration ?? 0),
                    bookmarkedAt: existing?.bookmarkedAt ?? Date(),
                    isUploaded: existing?.isUploaded ?? false
                )
                try entity.save(db)
            }
            // Unset bookmarked_at for albums no longer saved remotely
            if !remoteIds.isEmpty {
                let placeholders = DatabaseService.placeholders(count: remoteIds.count)
                try db.execute(
                    sql: "UPDATE album SET bookmarked_at = NULL WHERE bookmarked_at IS NOT NULL AND id NOT IN (\(placeholders))",
                    arguments: StatementArguments(Array(remoteIds))
                )
            }
        }
        return remoteIds
    }

    func syncSubscribedPodcasts() async throws -> Set<String> {
        let items = try await fetchAllPages(browseId: "FEmusic_library_non_music_audio_list") { json in
            LibraryBrowseParser.parsePodcasts(from: json)
        }
        let remoteIds = Set(items.map(\.browseId))
        try await db.write { db in
            for item in items {
                let existing = try PodcastEntity.fetchOne(db, key: item.browseId)
                let entity = PodcastEntity(
                    id: item.browseId,
                    name: item.name,
                    thumbnailUrl: item.thumbnailUrl ?? existing?.thumbnailUrl,
                    subscribedAt: existing?.subscribedAt ?? Date()
                )
                try entity.save(db)
            }
            // Unset subscribed_at for podcasts no longer subscribed remotely
            if !remoteIds.isEmpty {
                let placeholders = DatabaseService.placeholders(count: remoteIds.count)
                try db.execute(
                    sql: "UPDATE podcast SET subscribed_at = NULL WHERE subscribed_at IS NOT NULL AND id NOT IN (\(placeholders))",
                    arguments: StatementArguments(Array(remoteIds))
                )
            }
        }
        return remoteIds
    }

    /// Merges YTM's Liked Music auto-playlist (VLLM) into the permanent local
    /// Liked Songs list (`song.liked`), like Metrolist. The LM playlist row
    /// itself is deleted right away so it never appears in the library.
    /// Additive only — songs are never unliked by this sync.
    func syncLikedSongs() async throws -> Set<String> {
        _ = try await PlaylistDetailService.shared.fetchPlaylist(playlistId: "LM")
        let remoteIds = try await db.read { db in
            try Set(String.fetchAll(db, sql: "SELECT song_id FROM playlist_song_map WHERE playlist_id = 'LM'"))
        }
        try await db.write { db in
            if !remoteIds.isEmpty {
                // Mirror YTM's liked order in the local Liked Songs list, which
                // sorts by create_date: newest like first, staggered by shelf position.
                let orderedIds = try String.fetchAll(
                    db,
                    sql: "SELECT song_id FROM playlist_song_map WHERE playlist_id = 'LM' ORDER BY position"
                )
                let base = Date()
                for (index, songId) in orderedIds.enumerated() {
                    try db.execute(
                        sql: "UPDATE song SET liked = 1, modify_date = ?, create_date = ? WHERE id = ?",
                        arguments: [base, base.addingTimeInterval(TimeInterval(-index)), songId]
                    )
                }
            }
            try db.execute(sql: "DELETE FROM playlist_song_map WHERE playlist_id = 'LM'")
            try db.execute(sql: "DELETE FROM playlist WHERE id = 'LM'")
        }
        return remoteIds
    }

}

// MARK: Pagination

extension LibrarySyncService {
    private func fetchAllPages<T>(
        browseId: String,
        params: String? = nil,
        parse: @escaping ([String: Any]) -> [T]
    ) async throws -> [T] {
        try await innerTube.paginate(
            browseId: browseId,
            params: params,
            parse: parse,
            continuation: LibraryBrowseParser.extractContinuationToken(from:)
        )
    }
}
