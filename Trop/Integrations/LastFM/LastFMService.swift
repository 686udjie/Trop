//
//  LastFMService.swift
//  Trop
//

import Foundation

/// Coordinates Last.fm credentials, login, and scrobble / now-playing submissions.
@MainActor
@Observable
final class LastFMService {
    static let shared = LastFMService()

    private(set) var credentials: IntegrationCredentials.LastFMCredentials?
    private(set) var lastError: String?
    private(set) var isBusy = false

    /// Tracks which videoIds have already been scrobbled for the current play.
    private var scrobbledVideoIds: Set<String> = []
    private var lastNowPlayingVideoId: String?

    private init() {
        credentials = IntegrationCredentials.loadLastFM()
        Task { await applyClientConfig() }
    }

    var isLoggedIn: Bool {
        credentials?.isLoggedIn == true
    }

    var hasAPICredentials: Bool {
        credentials?.hasAPICredentials == true
    }

    var username: String? {
        credentials?.username
    }

    // MARK: - Credentials

    func saveAPICredentials(apiKey: String, apiSecret: String) async throws {
        var next = credentials ?? IntegrationCredentials.LastFMCredentials(apiKey: "", apiSecret: "")
        next.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        next.apiSecret = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        try IntegrationCredentials.saveLastFM(next)
        credentials = next
        await applyClientConfig()
        lastError = nil
        Log.lastfm.info("Saved Last.fm API credentials")
    }

    func login(username: String, password: String) async throws {
        guard hasAPICredentials else { throw LastFMError.notConfigured }
        isBusy = true
        defer { isBusy = false }
        do {
            await applyClientConfig()
            let auth = try await LastFMClient.shared.getMobileSession(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            var next = credentials!
            next.sessionKey = auth.session.key
            next.username = auth.session.name
            try IntegrationCredentials.saveLastFM(next)
            credentials = next
            await applyClientConfig()
            lastError = nil
            Log.lastfm.info("Logged in to Last.fm as \(auth.session.name)")
        } catch {
            lastError = error.localizedDescription
            Log.lastfm.error("Last.fm login failed: \(error.localizedDescription)")
            throw error
        }
    }

    func logout() throws {
        try IntegrationCredentials.clearLastFM()
        credentials = nil
        scrobbledVideoIds.removeAll()
        lastNowPlayingVideoId = nil
        Task { await LastFMClient.shared.configure(apiKey: "", apiSecret: "", sessionKey: nil) }
        lastError = nil
        Log.lastfm.info("Logged out of Last.fm")
    }

    // MARK: - Playback hooks

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
                try await LastFMClient.shared.updateNowPlaying(
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

        let settings = SettingsStore.shared
        let minDuration = settings.lastFMMinSongDuration
        guard track.duration >= minDuration || track.duration <= 0 else { return }

        let delaySeconds = settings.lastFMScrobbleDelaySeconds
        let delayPercent = settings.lastFMScrobbleDelayPercent
        let percentThreshold = track.duration > 0 ? track.duration * delayPercent : delaySeconds
        let threshold = min(max(percentThreshold, minDuration), delaySeconds)
        // Last.fm rule of thumb: scrobble after half the track or the configured delay.
        let effectiveThreshold = track.duration > 0
            ? min(threshold, track.duration * delayPercent)
            : delaySeconds
        let required = max(effectiveThreshold, minDuration)

        guard track.currentTime >= required else { return }

        submitScrobble(track, videoId: videoId, logLabel: "Scrobbled")
    }

    /// Fallback scrobble when playback ends after meeting the history threshold.
    func scrobbleIfNeededOnStop(_ track: LastFMTrackSnapshot) {
        guard SettingsStore.shared.lastFMEnabled, isLoggedIn else { return }
        guard let videoId = track.videoId, !track.title.isEmpty, !track.artist.isEmpty else { return }
        guard !scrobbledVideoIds.contains(videoId) else { return }

        let minDuration = SettingsStore.shared.lastFMMinSongDuration
        guard track.playTime >= minDuration else { return }

        if track.duration > 0 {
            let percent = SettingsStore.shared.lastFMScrobbleDelayPercent
            let delaySeconds = SettingsStore.shared.lastFMScrobbleDelaySeconds
            guard track.playTime >= track.duration * percent || track.playTime >= delaySeconds else {
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
                try await LastFMClient.shared.scrobble(
                    artist: track.artist,
                    track: track.title,
                    timestamp: timestamp,
                    album: track.album,
                    duration: durationSeconds
                )
                Log.lastfm.info("\(logLabel): \(track.artist) - \(track.title)")
            } catch {
                scrobbledVideoIds.remove(videoId)
                Log.lastfm.error("\(logLabel) failed: \(error.localizedDescription)")
            }
        }
    }

    private func applyClientConfig() async {
        let creds = credentials
        await LastFMClient.shared.configure(
            apiKey: creds?.apiKey ?? "",
            apiSecret: creds?.apiSecret ?? "",
            sessionKey: creds?.sessionKey
        )
    }
}
