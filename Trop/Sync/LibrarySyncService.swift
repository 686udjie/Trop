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
        try await db.write { db in
            for item in items {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO artist (id, name, thumbnail_url, bookmarked_at, is_podcast_channel, channel_id)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [item.browseId, item.name, item.thumbnailUrl,
                                     item.isSubscribed ? Date() : nil, false, item.channelId])
            }
        }
        return Set(items.map(\.browseId))
    }

    func syncLikedPlaylists() async throws -> Set<String> {
        let items = try await fetchAllPages(browseId: "FEmusic_liked_playlists") { json in
            LibraryBrowseParser.parsePlaylists(from: json)
        }
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
        }
        return Set(items.map(\.browseId))
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
