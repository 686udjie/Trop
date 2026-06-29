//
//  StreamCache.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import Foundation

/// In-memory cache for resolved stream URLs.
/// Entries expire after their TTL (expiresInSeconds from /player response).
actor StreamCache {
    static let shared = StreamCache()

    private var cache: [String: Entry] = [:]

    private struct Entry {
        let result: PlaybackResult
        let expiresAt: Date
    }

    private init() {}

    func get(videoId: String) -> PlaybackResult? {
        guard let entry = cache[videoId], entry.expiresAt > Date() else {
            cache.removeValue(forKey: videoId)
            return nil
        }
        return entry.result
    }

    func set(videoId: String, result: PlaybackResult) {
        let ttl = max(result.expiresInSeconds, 60)
        let entry = Entry(result: result, expiresAt: Date().addingTimeInterval(TimeInterval(ttl)))
        cache[videoId] = entry
        print("[StreamCache] Cached videoId=\(videoId) expires in \(ttl)s")
    }

    func remove(videoId: String) {
        cache.removeValue(forKey: videoId)
    }

    func clear() {
        cache.removeAll()
    }
}
