//
// DatabaseService.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Combine
import Foundation
import GRDB

actor DatabaseService {
    nonisolated static let shared = DatabaseService()

    let dbPool: DatabasePool

    init() {
        // swiftlint:disable:next force_try
        let url = try! FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("trop.sqlite")
        // swiftlint:disable:next force_try
        dbPool = try! DatabasePool(path: url.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1", migrate: DatabaseMigrations.v1)
        migrator.registerMigration("v2", migrate: DatabaseMigrations.v2)
        migrator.registerMigration("v3", migrate: DatabaseMigrations.v3)
        migrator.registerMigration("v4", migrate: DatabaseMigrations.v4)
        // swiftlint:disable:next force_try
        try! migrator.migrate(dbPool)
    }
}

// MARK: Generic CRUD

extension DatabaseService {
    func insert<T: MutablePersistableRecord & Sendable>(_ record: T) async throws -> T {
        try await dbPool.write { db -> T in
            var mutable = record
            try mutable.insert(db)
            return mutable
        }
    }

    func insert<T: MutablePersistableRecord & Sendable>(_ record: T, onConflict: Database.ConflictResolution) async throws -> T {
        try await dbPool.write { db -> T in
            var mutable = record
            try mutable.insert(db, onConflict: onConflict)
            return mutable
        }
    }

    func update<T: MutablePersistableRecord & Sendable>(_ record: T) async throws {
        try await dbPool.write { db in
            let mutable = record
            _ = try mutable.update(db)
        }
    }

    func save<T: MutablePersistableRecord & Sendable>(_ record: T) async throws {
        try await dbPool.write { db in
            var mutable = record
            _ = try mutable.save(db)
        }
    }

    @discardableResult
    func insertOrReplace<T: MutablePersistableRecord & Sendable>(_ record: T) async throws -> T {
        try await dbPool.write { db -> T in
            var mutable = record
            try mutable.insert(db, onConflict: .replace)
            return mutable
        }
    }

    @discardableResult
    func delete<T: MutablePersistableRecord & Sendable>(_ record: T) async throws -> Bool {
        try await dbPool.write { db -> Bool in
            let mutable = record
            return try mutable.delete(db)
        }
    }

    func fetchOne<T: FetchableRecord & TableRecord & Sendable>(_ type: T.Type, key: some DatabaseValueConvertible & Sendable) async throws -> T? {
        try await dbPool.read { db -> T? in
            try type.fetchOne(db, key: key)
        }
    }

    func fetchAll<T: FetchableRecord & TableRecord & Sendable>(_ type: T.Type) async throws -> [T] {
        try await dbPool.read { db -> [T] in
            try type.fetchAll(db)
        }
    }

    func fetchAll<T: FetchableRecord & TableRecord & Sendable>(_ type: T.Type, sql: String, arguments: StatementArguments = []) async throws -> [T] {
        try await dbPool.read { db -> [T] in
            try type.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    func write(_ block: @escaping @Sendable (Database) throws -> Void) async throws {
        try await dbPool.write { db in
            try block(db)
        }
    }

    func read<T: Sendable>(_ block: @escaping @Sendable (Database) throws -> T) async throws -> T {
        try await dbPool.read { db in
            try block(db)
        }
    }
}

// MARK: Playback Transactions

extension DatabaseService {
    func incrementTotalPlayTime(songId: String, playTimeMs: Int64) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: "UPDATE song SET total_play_time = total_play_time + ? WHERE id = ?",
                arguments: [playTimeMs, songId])
        }
    }

    func incrementPlayCount(songId: String, year: Int, month: Int) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO play_count (song_id, year, month, count)
                    VALUES (?, ?, ?, 1)
                    ON CONFLICT(song_id, year, month) DO UPDATE SET
                        count = count + 1
                    """,
                arguments: [songId, year, month])
        }
    }

    func insertEventIgnoringConflicts(_ event: Event) async throws -> Event {
        try await dbPool.write { db in
            let mutable = event
            try mutable.insert(db, onConflict: .ignore)
            return mutable
        }
    }

    func transferSongStats(from sourceSongId: String, to destSongId: String) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE song SET total_play_time = total_play_time + (
                        SELECT COALESCE(total_play_time, 0) FROM song WHERE id = ?
                    ) WHERE id = ?
                    """,
                arguments: [sourceSongId, destSongId])

            try db.execute(
                sql: "UPDATE OR IGNORE event SET song_id = ? WHERE song_id = ?",
                arguments: [destSongId, sourceSongId])

            try db.execute(
                sql: "DELETE FROM event WHERE song_id = ?",
                arguments: [sourceSongId])

            try db.execute(
                sql: """
                    INSERT INTO play_count (song_id, year, month, count)
                    SELECT ?, year, month, count FROM play_count WHERE song_id = ?
                    ON CONFLICT(song_id, year, month) DO UPDATE SET
                        count = play_count.count + excluded.count
                    """,
                arguments: [destSongId, sourceSongId])

            try db.execute(
                sql: "DELETE FROM play_count WHERE song_id = ?",
                arguments: [sourceSongId])

            try db.execute(
                sql: "DELETE FROM song WHERE id = ?",
                arguments: [sourceSongId])
        }
    }
}

enum LibrarySongSort: String, CaseIterable, Sendable {
    case recentlyAdded = "Recently Added"
    case title = "Title"
    case artist = "Artist"
    case mostPlayed = "Most Played"
}

// MARK: Personalization Queries

extension DatabaseService {

    /// Liked songs ordered by play count (for QuickPicks)
    func fetchLikedSongs() async throws -> [SongEntity] {
        try await dbPool.read { db in
            try SongEntity
                .filter(Column("liked") == true)
                .order(Column("total_play_time").desc)
                .limit(25)
                .fetchAll(db)
        }
    }

    /// Recently played songs (for KeepListening)
    func fetchRecentSongs(days: Int = 30, limit: Int = 20) async throws -> [SongEntity] {
        try await dbPool.read { db in
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let recentIds = try Event
                .filter(Column("timestamp") > cutoff)
                .select(Column("song_id"))
                .distinct()
                .order(Column("timestamp").desc)
                .limit(limit)
                .asRequest(of: String.self)
                .fetchAll(db)
            guard !recentIds.isEmpty else { return [] }
            let placeholders = recentIds.map { _ in "?" }.joined(separator: ",")
            return try SongEntity.fetchAll(db, sql: "SELECT * FROM song WHERE id IN (\(placeholders))", arguments: StatementArguments(recentIds))
        }
    }

    /// Forgotten favorites: liked songs not played in N days
    func fetchForgottenFavorites(days: Int = 60, limit: Int = 15) async throws -> [SongEntity] {
        try await dbPool.read { db in
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let df = ISO8601DateFormatter()
            let cutoffStr = df.string(from: cutoff)
            return try SongEntity.fetchAll(db, sql: """
                SELECT * FROM song
                WHERE liked = 1
                AND id NOT IN (SELECT DISTINCT song_id FROM event WHERE timestamp > ?)
                ORDER BY total_play_time ASC
                LIMIT ?
                """, arguments: [cutoffStr, limit])
        }
    }

    /// Most played albums (from liked/bookmarked albums)
    func fetchAlbums(limit: Int = 10) async throws -> [AlbumEntity] {
        try await dbPool.read { db in
            try AlbumEntity
                .order(Column("bookmarked_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Most played artists (from subscribed artists)
    func fetchArtists(limit: Int = 10) async throws -> [ArtistEntity] {
        try await dbPool.read { db in
            try ArtistEntity
                .filter(Column("bookmarked_at") != nil)
                .order(Column("name").asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// User's playlists
    func fetchPlaylists(limit: Int = 10) async throws -> [PlaylistEntity] {
        try await dbPool.read { db in
            try PlaylistEntity
                .filter(Column("bookmarked_at") != nil)
                .order(Column("bookmarked_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchAllLikedSongs(sort: LibrarySongSort = .recentlyAdded) async throws -> [SongEntity] {
        try await dbPool.read { db in
            var request = SongEntity.filter(Column("liked") == true)
            switch sort {
            case .title:
                request = request.order(Column("title").asc)
            case .artist:
                request = request.order(Column("artist_name").asc, Column("title").asc)
            case .recentlyAdded:
                request = request.order(Column("create_date").desc)
            case .mostPlayed:
                request = request.order(Column("total_play_time").desc)
            }
            return try request.fetchAll(db)
        }
    }

    func fetchAllAlbums() async throws -> [AlbumEntity] {
        try await dbPool.read { db in
            try AlbumEntity
                .order(Column("title").asc)
                .fetchAll(db)
        }
    }

    func fetchAllPodcasts() async throws -> [PodcastEntity] {
        try await dbPool.read { db in
            try PodcastEntity
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    func fetchAllLikedSongCount() async throws -> Int {
        try await dbPool.read { db in
            try SongEntity.filter(Column("liked") == true).fetchCount(db)
        }
    }

    func fetchTopSongs(limit: Int, from: Date, to: Date) async throws -> [SongEntity] {
        try await dbPool.read { db in
            try SongEntity.fetchAll(db, sql: """
                SELECT song.* FROM song
                LEFT JOIN (
                    SELECT song_id, SUM(play_time) AS total_time FROM event
                    WHERE timestamp >= ? AND timestamp <= ?
                    GROUP BY song_id
                ) AS top ON song.id = top.song_id
                WHERE song.liked = 1
                ORDER BY COALESCE(top.total_time, 0) DESC
                LIMIT ?
            """, arguments: [from, to, limit])
        }
    }
}

// MARK: Reactive Observation

extension DatabaseService {
    func observeAll<T: FetchableRecord & TableRecord & Sendable>(_ type: T.Type) -> AnyPublisher<[T], Error> {
        ValueObservation
            .tracking { db in try type.fetchAll(db) }
            .publisher(in: dbPool, scheduling: .async(onQueue: .main))
            .eraseToAnyPublisher()
    }

    func observeAll<T: FetchableRecord & TableRecord & Sendable>(
        _ type: T.Type,
        sql: String,
        arguments: StatementArguments = [])
        -> AnyPublisher<[T], Error>
    {
        ValueObservation
            .tracking { db in try type.fetchAll(db, sql: sql, arguments: arguments) }
            .publisher(in: dbPool, scheduling: .async(onQueue: .main))
            .eraseToAnyPublisher()
    }
}
