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

    func handleTrackChange(
        videoId: String?,
        title: String,
        artist: String,
        album: String?,
        duration: TimeInterval
    ) {
        guard SettingsStore.shared.lastFMEnabled, isLoggedIn else { return }
        guard let videoId, !title.isEmpty, !artist.isEmpty else { return }

        if lastNowPlayingVideoId != videoId {
            lastNowPlayingVideoId = videoId
            scrobbledVideoIds.remove(videoId)
        }

        guard SettingsStore.shared.lastFMUpdateNowPlaying else { return }
        let durationSeconds = duration > 0 ? Int(duration.rounded()) : nil
        Task {
            do {
                try await LastFMClient.shared.updateNowPlaying(
                    artist: artist,
                    track: title,
                    album: album,
                    duration: durationSeconds
                )
                Log.lastfm.debug("Updated now playing: \(artist) - \(title)")
            } catch {
                Log.lastfm.error("updateNowPlaying failed: \(error.localizedDescription)")
            }
        }
    }

    func considerScrobble(
        videoId: String?,
        title: String,
        artist: String,
        album: String?,
        currentTime: TimeInterval,
        duration: TimeInterval
    ) {
        guard SettingsStore.shared.lastFMEnabled, isLoggedIn else { return }
        guard let videoId, !title.isEmpty, !artist.isEmpty else { return }
        guard !scrobbledVideoIds.contains(videoId) else { return }

        let settings = SettingsStore.shared
        let minDuration = settings.lastFMMinSongDuration
        guard duration >= minDuration || duration <= 0 else { return }

        let delaySeconds = settings.lastFMScrobbleDelaySeconds
        let delayPercent = settings.lastFMScrobbleDelayPercent
        let percentThreshold = duration > 0 ? duration * delayPercent : delaySeconds
        let threshold = min(max(percentThreshold, minDuration), delaySeconds)
        // Last.fm rule of thumb: scrobble after half the track or the configured delay.
        let effectiveThreshold = duration > 0 ? min(threshold, duration * delayPercent) : delaySeconds
        let required = max(effectiveThreshold, minDuration)

        guard currentTime >= required else { return }

        scrobbledVideoIds.insert(videoId)
        let timestamp = Int(Date().timeIntervalSince1970)
        let durationSeconds = duration > 0 ? Int(duration.rounded()) : nil
        Task {
            do {
                try await LastFMClient.shared.scrobble(
                    artist: artist,
                    track: title,
                    timestamp: timestamp,
                    album: album,
                    duration: durationSeconds
                )
                Log.lastfm.info("Scrobbled: \(artist) - \(title)")
            } catch {
                scrobbledVideoIds.remove(videoId)
                Log.lastfm.error("Scrobble failed: \(error.localizedDescription)")
            }
        }
    }

    /// Fallback scrobble when playback ends after meeting the history threshold.
    func scrobbleIfNeededOnStop(
        videoId: String?,
        title: String,
        artist: String,
        album: String?,
        playTime: TimeInterval,
        duration: TimeInterval
    ) {
        guard SettingsStore.shared.lastFMEnabled, isLoggedIn else { return }
        guard let videoId, !title.isEmpty, !artist.isEmpty else { return }
        guard !scrobbledVideoIds.contains(videoId) else { return }

        let minDuration = SettingsStore.shared.lastFMMinSongDuration
        guard playTime >= minDuration else { return }

        if duration > 0 {
            let percent = SettingsStore.shared.lastFMScrobbleDelayPercent
            guard playTime >= duration * percent || playTime >= SettingsStore.shared.lastFMScrobbleDelaySeconds else {
                return
            }
        }

        scrobbledVideoIds.insert(videoId)
        let timestamp = Int(Date().timeIntervalSince1970)
        let durationSeconds = duration > 0 ? Int(duration.rounded()) : nil
        Task {
            do {
                try await LastFMClient.shared.scrobble(
                    artist: artist,
                    track: title,
                    timestamp: timestamp,
                    album: album,
                    duration: durationSeconds
                )
                Log.lastfm.info("Scrobbled on stop: \(artist) - \(title)")
            } catch {
                scrobbledVideoIds.remove(videoId)
                Log.lastfm.error("Scrobble on stop failed: \(error.localizedDescription)")
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
