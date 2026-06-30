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

    func syncAll() async throws -> LibrarySyncResult {
        let songs = try await syncLikedSongs()
        let albums = try await syncLikedAlbums()
        let artists = try await syncSubscribedArtists()
        let playlists = try await syncLikedPlaylists()
        return LibrarySyncResult(
            songIds: songs,
            albumIds: albums,
            artistIds: artists,
            playlistIds: playlists
        )
    }
}

// MARK: Section sync

extension LibrarySyncService {
    func syncLikedSongs() async throws -> Set<String> {
        let items = try await fetchAllPages(browseId: "FEmusic_library_songs") { json in
            LibraryBrowseParser.parseSongs(from: json)
        }
        try await db.write { db in
            for item in items {
                let existing = try SongEntity.fetchOne(db, key: item.videoId)
                let entity = SongEntity(
                    id: item.videoId,
                    title: item.title,
                    duration: item.duration,
                    thumbnailUrl: item.thumbnailUrl,
                    liked: true,
                    totalPlayTime: existing?.totalPlayTime ?? 0,
                    inLibrary: existing?.inLibrary ?? Date(),
                    libraryAddToken: item.libraryAddToken ?? existing?.libraryAddToken ?? "",
                    libraryRemoveToken: item.libraryRemoveToken ?? existing?.libraryRemoveToken ?? "",
                    isEpisode: false,
                    isUploaded: false,
                    isVideo: false,
                    createDate: existing?.createDate ?? Date(),
                    modifyDate: Date()
                )
                try entity.save(db)
            }
        }
        return Set(items.map(\.videoId))
    }

    func syncLikedAlbums() async throws -> Set<String> {
        let items = try await fetchAllPages(browseId: "FEmusic_liked_albums") { json in
            LibraryBrowseParser.parseAlbums(from: json)
        }
        try await db.write { db in
            for item in items {
                let existing = try AlbumEntity.fetchOne(db, key: item.browseId)
                let entity = AlbumEntity(
                    id: item.browseId,
                    title: item.title,
                    playlistId: item.playlistId ?? existing?.playlistId,
                    thumbnailUrl: item.thumbnailUrl ?? existing?.thumbnailUrl,
                    songCount: item.songCount > 0 ? item.songCount : (existing?.songCount ?? 0),
                    duration: item.duration > 0 ? item.duration : (existing?.duration ?? 0),
                    bookmarkedAt: existing?.bookmarkedAt ?? Date()
                )
                try entity.save(db)
            }
        }
        return Set(items.map(\.browseId))
    }

    func syncSubscribedArtists() async throws -> Set<String> {
        let items = try await fetchAllPages(browseId: "FEmusic_library_corpus_artists") { json in
            LibraryBrowseParser.parseArtists(from: json)
        }
        try await db.write { db in
            for item in items {
                let existing = try ArtistEntity.fetchOne(db, key: item.browseId)
                let entity = ArtistEntity(
                    id: item.browseId,
                    name: item.name,
                    thumbnailUrl: item.thumbnailUrl ?? existing?.thumbnailUrl,
                    bookmarkedAt: existing?.bookmarkedAt ?? (item.isSubscribed ? Date() : nil),
                    isPodcastChannel: existing?.isPodcastChannel ?? false
                )
                try entity.save(db)
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
