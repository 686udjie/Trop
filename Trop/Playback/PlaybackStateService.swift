//
// PlaybackStateService.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation
import GRDB

actor PlaybackStateService {
    nonisolated static let shared = PlaybackStateService()
    private let db = DatabaseService.shared
    private let innerTube = InnerTube.shared

    private let historyDurationThreshold: TimeInterval = 30.0
    private var currentVideoId: String?
    private var playbackStartTime: Date?
    private var isTracking = false

    private init() {}

    func startTracking(videoId: String) {
        currentVideoId = videoId
        playbackStartTime = Date()
        isTracking = true
    }

    func stopTracking() async {
        guard isTracking, let videoId = currentVideoId, let start = playbackStartTime else {
            reset()
            return
        }
        let elapsed = Date().timeIntervalSince(start)
        defer { reset() }

        if elapsed >= historyDurationThreshold {
            await recordPlayback(videoId: videoId, playTimeMs: Int64(elapsed * 1000))
        }
    }

    private func recordPlayback(videoId: String, playTimeMs: Int64) async {
        do {
            // Record local event
            var event = Event(id: nil, songId: videoId, timestamp: Date(), playTime: playTimeMs)
            event = try await db.insert(event, onConflict: .ignore)

            // Update play count
            let now = Date()
            let calendar = Calendar.current
            try await db.incrementPlayCount(songId: videoId, year: calendar.component(.year, from: now), month: calendar.component(.month, from: now))

            // Update total play time
            try await db.incrementTotalPlayTime(songId: videoId, playTimeMs: playTimeMs)

            // Call registerPlayback if we have a tracking URL cached
            let trackingUrl = await getCachedTrackingUrl(videoId: videoId)
            if let trackingUrl {
                try await RegisterPlaybackService.shared.registerPlayback(url: trackingUrl)
            }
        } catch {
            print("[PlaybackState] Failed to record playback: \(error)")
        }
    }

    private func getCachedTrackingUrl(videoId: String) async -> String? {
        // Check FormatEntity cache in DB
        if let format = try? await db.fetchOne(FormatEntity.self, key: videoId),
           let url = format.playbackUrl {
            return url
        }
        return nil
    }

    private func reset() {
        currentVideoId = nil
        playbackStartTime = nil
        isTracking = false
    }
}
