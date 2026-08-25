//
//  DurationCache.swift
//  Trop
//
//  Created by 686udjie on 02/07/2026.
//

import Foundation

extension Notification.Name {
    static let durationDidUpdate = Notification.Name("durationDidUpdate")
}

enum DurationCache {
    private static var cache: [String: Int] = [:]
    private static var pending: Set<String> = []
    private static var inFlight: [String: Task<Int, Error>] = [:]
    private static let lock = NSLock()

    static func isPending(_ videoId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pending.contains(videoId)
    }

    static func get(_ videoId: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return cache[videoId]
    }

    static func set(_ videoId: String, _ duration: Int) {
        lock.lock()
        cache[videoId] = duration
        pending.remove(videoId)
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .durationDidUpdate,
                object: nil,
                userInfo: ["videoId": videoId, "duration": duration]
            )
        }
    }

    static func markPending(_ videoId: String) {
        lock.lock(); defer { lock.unlock() }
        pending.insert(videoId)
    }

    static func clearPending(_ videoId: String) {
        lock.lock(); defer { lock.unlock() }
        pending.remove(videoId)
    }

    /// Deduplicates concurrent duration fetches for the same video ID.
    static func resolve(
        videoId: String,
        fetch: @escaping @Sendable () async throws -> Int
    ) async throws -> Int {
        lock.lock()
        if let cached = cache[videoId], cached > 0 {
            lock.unlock()
            return cached
        }
        if let existing = inFlight[videoId] {
            lock.unlock()
            return try await existing.value
        }

        let task = Task<Int, Error> {
            try await fetch()
        }
        inFlight[videoId] = task
        pending.insert(videoId)
        lock.unlock()

        defer {
            lock.lock()
            inFlight.removeValue(forKey: videoId)
            pending.remove(videoId)
            lock.unlock()
        }

        return try await task.value
    }
}
