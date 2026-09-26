//
//  AppDependencies.swift
//  Trop
//
//  Created by 686udjie on 26/09/2026.
//

import Foundation

// MARK: - Playback

protocol StreamResolving {
    func resolve(videoId: String) async throws -> PlaybackResult
    func resolveAndPlay(videoId: String) async throws
}

// MARK: - Queue persistence

struct PersistedQueue {
    var songs: [SongItem]
    var index: Int
    var shuffle: Bool
    var repeatOne: Bool
}

protocol QueuePersisting {
    func saveQueue(_ songs: [SongItem], index: Int, shuffle: Bool, repeatOne: Bool)
    func loadQueue() -> PersistedQueue?
    func clearQueue()
}

struct UserDefaultsQueuePersistence: QueuePersisting {
    private let queueKey = "nowPlaying.queue"
    private let queueIndexKey = "nowPlaying.queueIndex"
    private let shuffleKey = "nowPlaying.shuffle"
    private let repeatKey = "nowPlaying.repeat"

    func saveQueue(_ songs: [SongItem], index: Int, shuffle: Bool, repeatOne: Bool) {
        if songs.isEmpty {
            UserDefaults.standard.removeObject(forKey: queueKey)
            UserDefaults.standard.removeObject(forKey: queueIndexKey)
            UserDefaults.standard.removeObject(forKey: shuffleKey)
            UserDefaults.standard.removeObject(forKey: repeatKey)
            return
        }
        if let data = try? JSONEncoder().encode(songs) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
        UserDefaults.standard.set(index, forKey: queueIndexKey)
        UserDefaults.standard.set(shuffle, forKey: shuffleKey)
        UserDefaults.standard.set(repeatOne, forKey: repeatKey)
    }

    func loadQueue() -> PersistedQueue? {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
              let songs = try? JSONDecoder().decode([SongItem].self, from: data),
              !songs.isEmpty else { return nil }
        let storedIndex: Int
        if UserDefaults.standard.object(forKey: queueIndexKey) != nil {
            storedIndex = UserDefaults.standard.integer(forKey: queueIndexKey)
        } else {
            storedIndex = 0
        }
        let index = min(max(storedIndex, 0), songs.count - 1)
        let shuffle = UserDefaults.standard.bool(forKey: shuffleKey)
        let repeatOne = UserDefaults.standard.bool(forKey: repeatKey)
        return PersistedQueue(songs: songs, index: index, shuffle: shuffle, repeatOne: repeatOne)
    }

    func clearQueue() {
        UserDefaults.standard.removeObject(forKey: queueKey)
        UserDefaults.standard.removeObject(forKey: queueIndexKey)
        UserDefaults.standard.removeObject(forKey: shuffleKey)
        UserDefaults.standard.removeObject(forKey: repeatKey)
    }
}

// MARK: - Container

enum AppDependencies {
    static var queuePersistence: any QueuePersisting = UserDefaultsQueuePersistence()
}
