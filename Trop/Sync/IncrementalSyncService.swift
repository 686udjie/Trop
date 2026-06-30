//
// IncrementalSyncService.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation

actor IncrementalSyncService {
    nonisolated static let shared = IncrementalSyncService()
    private let librarySync = LibrarySyncService.shared
    private let innerTube = InnerTube.shared
    private let defaults = UserDefaults.standard

    private let lastSyncKey = "lastSyncTimestamp"
    private let syncThreshold: TimeInterval = 15 * 60 // 15 minutes

    private init() {}

    var lastSyncDate: Date? {
        defaults.object(forKey: lastSyncKey) as? Date
    }

    func checkAndSyncIfStale() async throws -> Bool {
        let lastSync = lastSyncDate ?? .distantPast
        guard Date().timeIntervalSince(lastSync) >= syncThreshold else {
            print("[Sync] Last sync was recent, skipping")
            return false
        }
        try await forceFullSync()
        return true
    }

    func forceFullSync() async throws {
        // Verify login first
        guard (try? await innerTube.accountMenu()) != nil else {
            print("[Sync] Not logged in, skipping sync")
            return
        }

        let result = try await librarySync.syncAll()
        defaults.set(Date(), forKey: lastSyncKey)
        print("[Sync] Full sync complete: \(result.songIds.count) songs, \(result.albumIds.count) albums, \(result.artistIds.count) artists, \(result.playlistIds.count) playlists")
    }

    // Token-based incremental sync: send feedback tokens to push local state changes
    func pushFeedbackTokens(addTokens: [String], removeTokens: [String]) async throws {
        let allTokens = addTokens + removeTokens
        guard !allTokens.isEmpty else { return }
        _ = try await innerTube.feedback(tokens: allTokens)
        defaults.set(Date(), forKey: lastSyncKey)
    }

    func clearSyncTimestamp() {
        defaults.removeObject(forKey: lastSyncKey)
    }
}
