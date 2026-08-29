//
//  LastFMScrobbler.swift
//  Trop
//

import Foundation

/// Coordinates Last.fm session + scrobble / now-playing submissions.
@MainActor
@Observable
final class LastFMScrobbler {
    static let shared = LastFMScrobbler()

    private(set) var username: String?
    private(set) var lastError: String?
    private(set) var isBusy = false
    private(set) var isConfigured = false

    private var scrobbledVideoIds: Set<String> = []
    private var lastNowPlayingVideoId: String?

    private init() {}

    var isLoggedIn: Bool {
        LastFMSessionStore.isLoggedIn
    }

    func restoreSession() {
        let config = IntegrationsConfig.load()
        isConfigured = !config.lastFMAPIKey.isEmpty && !config.lastFMAPISecret.isEmpty
        username = LastFMSessionStore.username
        Task {
            await LastFM.shared.configure(
                apiKey: config.lastFMAPIKey,
                apiSecret: config.lastFMAPISecret,
                sessionKey: LastFMSessionStore.sessionKey
            )
        }
    }

    func beginAuthorization() async throws -> (url: URL, token: String) {
        let config = IntegrationsConfig.load()
        guard !config.lastFMAPIKey.isEmpty, !config.lastFMAPISecret.isEmpty else {
            throw LastFMError.notConfigured
        }
        isConfigured = true
        isBusy = true
        defer { isBusy = false }
        await LastFM.shared.configure(
            apiKey: config.lastFMAPIKey,
            apiSecret: config.lastFMAPISecret,
            sessionKey: LastFMSessionStore.sessionKey
        )
        let token = try await LastFM.shared.getToken()
        let url = await LastFM.shared.authURL(token: token)
        return (url, token)
    }

    func completeAuthorization(_ auth: LastFMAuthentication) async {
        LastFMSessionStore.save(sessionKey: auth.session.key, username: auth.session.name)
        username = auth.session.name
        await LastFM.shared.setSessionKey(auth.session.key)
        lastError = nil
        SettingsStore.shared.lastFMEnabled = true
        Log.lastfm.info("Logged in to Last.fm as \(auth.session.name)")
    }

    func logout() {
        LastFMSessionStore.clear()
        username = nil
        scrobbledVideoIds.removeAll()
        lastNowPlayingVideoId = nil
        Task { await LastFM.shared.setSessionKey(nil) }
        SettingsStore.shared.lastFMEnabled = false
        lastError = nil
        Log.lastfm.info("Logged out of Last.fm")
    }

    func handleTrackChange(_ track: LastFMTrackSnapshot) {
        guard SettingsStore.shared.lastFMEnabled, isLoggedIn else { return }
        guard let videoId = track.videoId, !track.title.isEmpty, !track.artist.isEmpty else { return }

        if lastNowPlayingVideoId != videoId {
            lastNowPlayingVideoId = videoId
            scrobbledVideoIds.remove(videoId)
        }

        guard SettingsStore.shared.lastFMUpdateNowPlaying else { return }
        let durationSeconds = track.duration > 0 ? Int(track.duration.rounded()) : nil
        Task {
            do {
                try await LastFM.shared.updateNowPlaying(
                    artist: track.artist,
                    track: track.title,
                    album: track.album,
                    duration: durationSeconds
                )
                Log.lastfm.debug("Updated now playing: \(track.artist) - \(track.title)")
            } catch {
                Log.lastfm.error("updateNowPlaying failed: \(error.localizedDescription)")
            }
        }
    }

    func considerScrobble(_ track: LastFMTrackSnapshot) {
        guard SettingsStore.shared.lastFMEnabled, isLoggedIn else { return }
        guard let videoId = track.videoId, !track.title.isEmpty, !track.artist.isEmpty else { return }
        guard !scrobbledVideoIds.contains(videoId) else { return }

        let percent = SettingsStore.shared.lastFMScrobbleDelayPercent
        let maxDelay = SettingsStore.shared.lastFMScrobbleDelaySeconds
        let minDuration = SettingsStore.shared.lastFMMinSongDuration

        guard track.duration >= minDuration || track.duration <= 0 else { return }

        let percentThreshold = track.duration > 0 ? track.duration * percent : maxDelay
        let required = min(max(percentThreshold, minDuration), maxDelay)

        guard track.currentTime >= required else { return }
        submitScrobble(track, videoId: videoId, logLabel: "Scrobbled")
    }

    func scrobbleIfNeededOnStop(_ track: LastFMTrackSnapshot) {
        guard SettingsStore.shared.lastFMEnabled, isLoggedIn else { return }
        guard let videoId = track.videoId, !track.title.isEmpty, !track.artist.isEmpty else { return }
        guard !scrobbledVideoIds.contains(videoId) else { return }

        let minDuration = SettingsStore.shared.lastFMMinSongDuration
        guard track.playTime >= minDuration else { return }

        if track.duration > 0 {
            let percent = SettingsStore.shared.lastFMScrobbleDelayPercent
            let delay = SettingsStore.shared.lastFMScrobbleDelaySeconds
            guard track.playTime >= track.duration * percent || track.playTime >= delay else {
                return
            }
        }

        submitScrobble(track, videoId: videoId, logLabel: "Scrobbled on stop")
    }

    private func submitScrobble(_ track: LastFMTrackSnapshot, videoId: String, logLabel: String) {
        scrobbledVideoIds.insert(videoId)
        let timestamp = Int(Date().timeIntervalSince1970)
        let durationSeconds = track.duration > 0 ? Int(track.duration.rounded()) : nil
        Task {
            do {
                try await LastFM.shared.scrobble(
                    artist: track.artist,
                    track: track.title,
                    timestamp: timestamp,
                    album: track.album,
                    duration: durationSeconds
                )
                Log.lastfm.info("\(logLabel): \(track.artist) - \(track.title)")
            } catch {
                scrobbledVideoIds.remove(videoId)
                lastError = error.localizedDescription
                Log.lastfm.error("\(logLabel) failed: \(error.localizedDescription)")
            }
        }
    }
}

/// Playback metadata for Last.fm hooks.
struct LastFMTrackSnapshot: Equatable {
    var videoId: String?
    var title: String
    var artist: String
    var album: String?
    var duration: TimeInterval
    var currentTime: TimeInterval = 0
    var playTime: TimeInterval = 0
}
