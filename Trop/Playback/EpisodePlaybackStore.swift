//
//  EpisodePlaybackStore.swift
//  Trop
//
//  Created by 686udjie on 26/09/2026.
//

import Foundation

/// Saved playback position for one episode.
struct EpisodePosition: Codable {
    var position: Double
    var duration: Double
    var updatedAt: Date

    var remaining: Double { max(0, duration - position) }
    /// Considered finished when <30s remains or >95% watched.
    var isFinished: Bool {
        guard duration > 0 else { return false }
        return remaining < 30 || position / duration > 0.95
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }
}

actor EpisodePlaybackStore {
    static let shared = EpisodePlaybackStore()

    private let positionsKey = "episode.positions.v1"
    private var positions: [String: EpisodePosition] = [:]
    private var loaded = false

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        if let data = UserDefaults.standard.data(forKey: positionsKey),
           let decoded = try? JSONDecoder().decode([String: EpisodePosition].self, from: data) {
            positions = decoded
        }
    }

    private func persist() {
        // Cap to the 200 most recently updated so the blob can't grow unbounded.
        if positions.count > 200 {
            let sorted = positions.sorted { $0.value.updatedAt > $1.value.updatedAt }
            positions = Dictionary(uniqueKeysWithValues: sorted.prefix(200).map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(positions) {
            UserDefaults.standard.set(data, forKey: positionsKey)
        }
    }

    func position(for videoId: String) -> EpisodePosition? {
        ensureLoaded()
        return positions[videoId]
    }

    /// Saves position throttled by the caller (NowPlaying ticks 4x/sec —
    /// only persist every ~5s or on pause/seek).
    func savePosition(videoId: String, position: Double, duration: Double) {
        ensureLoaded()
        guard duration > 0, position >= 0 else { return }
        let existing = positions[videoId]
        // Throttle: skip writes <5s apart unless finished/near-zero.
        if let existing,
           abs(existing.position - position) < 5,
           Date().timeIntervalSince(existing.updatedAt) < 5,
           !EpisodePosition(position: position, duration: duration, updatedAt: Date()).isFinished {
            return
        }
        positions[videoId] = EpisodePosition(position: position, duration: duration, updatedAt: Date())
        persist()
    }

    func clearPosition(videoId: String) {
        ensureLoaded()
        positions.removeValue(forKey: videoId)
        persist()
    }

    // MARK: - Played tracking

    func markPlayed(videoId: String) async {
        let entity: EpisodeEntity? = (try? await DatabaseService.shared.fetchOne(EpisodeEntity.self, key: videoId)) ?? nil
        if var entity {
            entity.isPlayed = true
            try? await DatabaseService.shared.save(entity)
        }
        clearPosition(videoId: videoId)
    }

    func syncKnownEpisodes(_ episodes: [EpisodeItem], podcastId: String?, podcastName: String?) async -> [EpisodeItem] {
        var fresh: [EpisodeItem] = []
        for episode in episodes {
            let existing: EpisodeEntity? = (try? await DatabaseService.shared.fetchOne(EpisodeEntity.self, key: episode.videoId)) ?? nil
            if existing == nil {
                fresh.append(episode)
                let entity = EpisodeEntity(
                    id: episode.videoId,
                    title: episode.title,
                    duration: episode.duration,
                    thumbnailUrl: episode.thumbnailUrl,
                    podcastId: podcastId,
                    podcastName: podcastName,
                    isPlayed: false,
                    savedAt: Date()
                )
                _ = try? await DatabaseService.shared.insertOrReplace(entity)
            }
        }
        return fresh
    }
}
