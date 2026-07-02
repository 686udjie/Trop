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
            NotificationCenter.default.post(name: .durationDidUpdate, object: nil, userInfo: ["videoId": videoId])
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
}
