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
        do { result.artistIds = try await syncSubscribedArtists() } catch { print("syncSubscribedArtists error: \(error)") }
        do { result.playlistIds = try await syncLikedPlaylists() } catch { print("syncLikedPlaylists error: \(error)") }
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
                let placeholders = remoteIds.map { _ in "?" }.joined(separator: ",")
                try db.execute(sql: "UPDATE artist SET bookmarked_at = NULL WHERE bookmarked_at IS NOT NULL AND id NOT IN (\(placeholders))", arguments: StatementArguments(Array(remoteIds)))
            }
        }
        return remoteIds
    }

    func syncLikedPlaylists() async throws -> Set<String> {
        let items = try await fetchAllPages(browseId: "FEmusic_liked_playlists") { json in
            LibraryBrowseParser.parsePlaylists(from: json)
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
                    remoteSongCount: item.songCount ?? existing?.remoteSongCount
                )
                try entity.save(db)
            }
            // Remove playlists unliked remotely — only those that have a browseId (synced), not local-only playlists
            if !remoteIds.isEmpty {
                try db.execute(sql: """
                    DELETE FROM playlist_song_map WHERE playlist_id IN (
                        SELECT id FROM playlist WHERE browse_id IS NOT NULL AND browse_id NOT IN (\(remoteIds.map { _ in "?" }.joined(separator: ",")))
                    )
                    """, arguments: StatementArguments(Array(remoteIds)))
                try db.execute(sql: """
                    DELETE FROM playlist WHERE browse_id IS NOT NULL AND browse_id NOT IN (\(remoteIds.map { _ in "?" }.joined(separator: ",")))
                    """, arguments: StatementArguments(Array(remoteIds)))
            }
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
        var allItems: [T] = []
        var continuation: String?
        repeat {
            let json = try await innerTube.browse(
                browseId: browseId,
                params: params,
                continuation: continuation
            )
            let items = parse(json)
            allItems.append(contentsOf: items)
            continuation = LibraryBrowseParser.extractContinuationToken(from: json)
        } while continuation != nil
        return allItems
    }
}
