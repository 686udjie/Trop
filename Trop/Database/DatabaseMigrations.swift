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
}
