//
// DatabaseMigrations.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

enum DatabaseMigrations {
    static let v1: (Database) throws -> Void = { db in
        try db.create(table: "song") { t in
            t.column("id", .text).primaryKey()
            t.column("title", .text).notNull()
            t.column("duration", .integer).notNull()
            t.column("thumbnail_url", .text)
            t.column("liked", .integer).notNull().defaults(to: false)
            t.column("total_play_time", .integer).notNull().defaults(to: 0)
            t.column("in_library", .text)
            t.column("library_add_token", .text).notNull().defaults(to: "")
            t.column("library_remove_token", .text).notNull().defaults(to: "")
            t.column("is_episode", .integer).notNull().defaults(to: false)
            t.column("is_uploaded", .integer).notNull().defaults(to: false)
            t.column("is_video", .integer).notNull().defaults(to: false)
            t.column("create_date", .text).notNull()
            t.column("modify_date", .text).notNull()
        }

        try db.create(table: "artist") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("thumbnail_url", .text)
            t.column("bookmarked_at", .text)
            t.column("is_podcast_channel", .integer).notNull().defaults(to: false)
        }

        try db.create(table: "album") { t in
            t.column("id", .text).primaryKey()
            t.column("title", .text).notNull()
            t.column("playlist_id", .text)
            t.column("thumbnail_url", .text)
            t.column("song_count", .integer).notNull().defaults(to: 0)
            t.column("duration", .integer).notNull().defaults(to: 0)
            t.column("bookmarked_at", .text)
        }

        try db.create(table: "playlist") { t in
            t.column("id", .text).primaryKey()
            t.column("browse_id", .text)
            t.column("name", .text).notNull()
            t.column("is_editable", .integer).notNull().defaults(to: false)
            t.column("bookmarked_at", .text)
            t.column("remote_song_count", .integer)
        }

        try db.create(table: "playlist_song_map") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("playlist_id", .text).notNull()
            t.column("song_id", .text).notNull()
            t.column("position", .integer).notNull()
            t.column("set_video_id", .text)
            t.uniqueKey(["playlist_id", "song_id"])
        }

        try db.create(table: "event") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("song_id", .text).notNull()
            t.column("timestamp", .text).notNull()
            t.column("play_time", .integer).notNull()
            t.uniqueKey(["song_id", "timestamp"])
        }

        try db.create(table: "play_count") { t in
            t.column("song_id", .text).notNull()
            t.column("year", .integer).notNull()
            t.column("month", .integer).notNull()
            t.column("count", .integer).notNull().defaults(to: 0)
            t.primaryKey(["song_id", "year", "month"])
        }

        try db.create(table: "format") { t in
            t.column("id", .text).primaryKey()
            t.column("itag", .integer).notNull()
            t.column("mime_type", .text).notNull()
            t.column("codecs", .text).notNull()
            t.column("bitrate", .integer).notNull()
            t.column("sample_rate", .integer).notNull()
            t.column("content_length", .integer).notNull()
            t.column("loudness_db", .double)
            t.column("perceptual_loudness_db", .double)
            t.column("playback_url", .text)
        }
    }

    static let v2: (Database) throws -> Void = { db in
        try db.alter(table: "song") { t in
            t.add(column: "artist_name", .text)
            t.add(column: "album_name", .text)
        }
    }

    static let v3: (Database) throws -> Void = { db in
        print("[DB] Running v3 migration")
        try db.alter(table: "artist") { t in
            t.add(column: "channel_id", .text)
        }

        try db.alter(table: "album") { t in
            t.add(column: "is_uploaded", .integer).notNull().defaults(to: false)
        }

        try db.alter(table: "playlist") { t in
            t.add(column: "is_auto_sync", .integer).notNull().defaults(to: false)
        }

        try db.create(table: "episode") { t in
            t.column("id", .text).primaryKey()
            t.column("title", .text).notNull()
            t.column("duration", .integer).notNull()
            t.column("thumbnail_url", .text)
            t.column("podcast_id", .text)
            t.column("podcast_name", .text)
            t.column("is_played", .integer).notNull().defaults(to: false)
            t.column("saved_at", .text)
        }

        try db.create(table: "podcast") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("thumbnail_url", .text)
            t.column("subscribed_at", .text)
        }

        try db.create(table: "podcast_episode_map") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("podcast_id", .text).notNull()
            t.column("episode_id", .text).notNull()
            t.column("position", .integer).notNull()
            t.uniqueKey(["podcast_id", "episode_id"])
        }
        print("[DB] v3 migration complete")
    }

    static let v4: (Database) throws -> Void = { db in
        print("[DB] Running v4 migration")
        try db.alter(table: "playlist") { t in
            t.add(column: "thumbnail_url", .text)
        }
        print("[DB] v4 migration complete")
    }

    static let v5: (Database) throws -> Void = { db in
        print("[DB] Running v5 migration")
        if try db.tableExists("downloaded_track") == false {
            try db.create(table: "downloaded_track") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("duration", .integer).notNull()
                t.column("thumbnail_url", .text)
                t.column("local_path", .text).notNull()
                t.column("downloaded_at", .text).notNull()
            }
        } else if try db.columns(in: "downloaded_track").contains(where: { $0.name == "artist" }) == false {
            // Table existed from an earlier schema without the artist column.
            try db.alter(table: "downloaded_track") { t in
                t.add(column: "artist", .text).notNull().defaults(to: "")
            }
        }
        print("[DB] v5 migration complete")
    }

    static let v6: (Database) throws -> Void = { db in
        print("[DB] Running v6 migration")
        // Earlier schemas may have created downloaded_track with fewer columns
        // than DownloadedTrackEntity expects. Add any missing columns so inserts
        // from the app succeed on existing databases.
        if try db.tableExists("downloaded_track") {
            let existing = try db.columns(in: "downloaded_track").map(\.name)
            let required: [(name: String, type: Database.ColumnType, notNull: Bool)] = [
                ("artist", .text, true),
                ("thumbnail_url", .text, false),
                ("local_path", .text, true),
                ("downloaded_at", .text, true),
                ("duration", .integer, true),
                ("title", .text, true)
            ]
            for col in required where !existing.contains(col.name) {
                try db.alter(table: "downloaded_track") { t in
                    let added = t.add(column: col.name, col.type)
                    if col.notNull {
                        added.notNull().defaults(to: col.name == "downloaded_at" ? "" : "")
                    }
                }
            }
        }
        print("[DB] v6 migration complete")
    }

    static let v7: (Database) throws -> Void = { db in
        print("[DB] Running v7 migration")
        // The existing downloaded_track table may have been created by an older
        // schema (e.g. with a file_size column) that doesn't match
        // DownloadedTrackEntity. Rebuild it to exactly match the entity,
        // preserving any rows we can carry over by id.
        if try db.tableExists("downloaded_track") {
            try db.create(table: "downloaded_track_new") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("duration", .integer).notNull()
                t.column("thumbnail_url", .text)
                t.column("local_path", .text).notNull()
                t.column("downloaded_at", .text).notNull()
            }
            // Carry over rows that have the columns we need (id + local_path).
            if try db.columns(in: "downloaded_track").contains(where: { $0.name == "local_path" }) {
                // Use a real ISO8601 timestamp for any row missing downloaded_at,
                // so GRDB can decode it back into a Date on fetch.
                let fallbackDate = ISO8601DateFormatter().string(from: Date())
                try db.execute(
                    sql: """
                        INSERT INTO downloaded_track_new (id, title, artist, duration, thumbnail_url, local_path, downloaded_at)
                        SELECT id,
                               COALESCE(title, ''),
                               COALESCE(artist, ''),
                               COALESCE(duration, 0),
                               thumbnail_url,
                               local_path,
                               COALESCE(NULLIF(downloaded_at, ''), ?)
                        FROM downloaded_track
                        WHERE local_path IS NOT NULL
                    """,
                    arguments: [fallbackDate]
                )
            }
            try db.drop(table: "downloaded_track")
            try db.rename(table: "downloaded_track_new", to: "downloaded_track")
        }
        print("[DB] v7 migration complete")
    }
}
