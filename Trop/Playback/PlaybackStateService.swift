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
    private var hasRecordedPlayback = false
    private var periodicCheckTask: Task<Void, Never>?

    private init() {}

    func startTracking(videoId: String) {
        currentVideoId = videoId
        playbackStartTime = Date()
        isTracking = true
        hasRecordedPlayback = false
        print("[PlaybackState] Started tracking videoId=\(videoId)")

        periodicCheckTask?.cancel()
        periodicCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, let start = await self.playbackStartTime, await self.isTracking else { return }
                let elapsed = Date().timeIntervalSince(start)
                if elapsed >= self.historyDurationThreshold, !(await self.hasRecordedPlayback) {
                    await self.firePlayback(videoId: await self.currentVideoId ?? "", playTimeMs: Int64(elapsed * 1000))
                }
            }
        }
    }

    func stopTracking() async {
        periodicCheckTask?.cancel()
        periodicCheckTask = nil

        guard isTracking, let videoId = currentVideoId, let start = playbackStartTime else {
            print("[PlaybackState] stopTracking called but no active tracking")
            reset()
            return
        }
        let elapsed = Date().timeIntervalSince(start)
        print("[PlaybackState] Stopped tracking videoId=\(videoId) totalElapsed=\(String(format: "%.1f", elapsed))s")
        defer { reset() }

        if elapsed >= historyDurationThreshold, !hasRecordedPlayback {
            await firePlayback(videoId: videoId, playTimeMs: Int64(elapsed * 1000))
        } else if elapsed < historyDurationThreshold {
            print("[PlaybackState] Elapsed \(String(format: "%.1f", elapsed))s below threshold \(self.historyDurationThreshold)s — skipping history recording")
        }
    }

    private func firePlayback(videoId: String, playTimeMs: Int64) async {
        hasRecordedPlayback = true
        await recordPlayback(videoId: videoId, playTimeMs: playTimeMs)
    }

    private func recordPlayback(videoId: String, playTimeMs: Int64) async {
        print("[PlaybackState] Recording playback videoId=\(videoId) playTimeMs=\(playTimeMs)")
        do {
            var event = Event(id: nil, songId: videoId, timestamp: Date(), playTime: playTimeMs)
            event = try await db.insert(event, onConflict: .ignore)
            print("[PlaybackState] Local event recorded id=\(event.id ?? 0)")

            let now = Date()
            let calendar = Calendar.current
            try await db.incrementPlayCount(songId: videoId, year: calendar.component(.year, from: now), month: calendar.component(.month, from: now))
            print("[PlaybackState] Play count incremented")

            try await db.incrementTotalPlayTime(songId: videoId, playTimeMs: playTimeMs)
            print("[PlaybackState] Total play time incremented")

            let trackingUrl = await getCachedTrackingUrl(videoId: videoId)
            if let trackingUrl {
                print("[PlaybackState] Sending playback to YTM via RegisterPlaybackService")
                try await RegisterPlaybackService.shared.registerPlayback(url: trackingUrl)
            } else {
                print("[PlaybackState] No cached tracking URL for videoId=\(videoId) — skipping YTM registration")
            }
        } catch {
            print("[PlaybackState] Failed to record playback: \(error)")
        }
    }

    private func getCachedTrackingUrl(videoId: String) async -> String? {
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
