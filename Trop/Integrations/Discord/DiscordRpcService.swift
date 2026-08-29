//
//  DiscordRpcService.swift
//  Trop
//

import Foundation

/// Classic Discord Rich Presence over the gateway (user token + STATUS_UPDATE).
@MainActor
@Observable
final class DiscordRpcService {
    static let shared = DiscordRpcService()

    enum ConnectionStatus: String {
        case disconnected = "Disconnected"
        case connecting = "Connecting"
        case connected = "Connected"
    }

    private(set) var credentials: IntegrationCredentials.DiscordCredentials?
    private(set) var connectionStatus: ConnectionStatus = .disconnected
    private(set) var lastError: String?

    private let gateway = DiscordGateway()
    private var lastVideoId: String?
    private var lastIsPlaying: Bool?
    private var activityStartedAt: Int64?
    private var throttleTask: Task<Void, Never>?

    private init() {
        credentials = IntegrationCredentials.loadDiscord()
    }

    var isLoggedIn: Bool {
        credentials?.isLoggedIn == true
    }

    var username: String? {
        credentials?.username
    }

    // MARK: - Auth

    func saveToken(_ token: String, username: String?) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let creds = IntegrationCredentials.DiscordCredentials(
            token: trimmed,
            username: username,
            userId: nil
        )
        try IntegrationCredentials.saveDiscord(creds)
        credentials = creds
        lastError = nil
        Log.discord.info("Saved Discord token")
        if SettingsStore.shared.discordRPCEnabled {
            Task { await connectIfNeeded() }
        }
    }

    func logout() async {
        try? IntegrationCredentials.clearDiscord()
        credentials = nil
        await gateway.disconnect()
        connectionStatus = .disconnected
        lastVideoId = nil
        lastIsPlaying = nil
        activityStartedAt = nil
        lastError = nil
        Log.discord.info("Logged out of Discord RPC")
    }

    func connectIfNeeded() async {
        guard SettingsStore.shared.discordRPCEnabled, isLoggedIn,
              let token = credentials?.token else {
            await gateway.disconnect()
            connectionStatus = .disconnected
            return
        }
        connectionStatus = .connecting
        let appId = SettingsStore.shared.discordApplicationId
            .trimmingCharacters(in: .whitespacesAndNewlines)
        await gateway.connect(token: token, applicationId: appId)
        // Poll gateway status briefly.
        for _ in 0..<20 {
            let status = await gateway.status
            if status == .connected {
                connectionStatus = .connected
                lastError = nil
                await pushNowPlaying(force: true)
                return
            }
            if status == .disconnected {
                break
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        let finalStatus = await gateway.status
        connectionStatus = finalStatus == .connected ? .connected : .disconnected
        if connectionStatus == .disconnected {
            lastError = "Could not connect to Discord gateway"
        }
    }

    func disconnect() async {
        await gateway.clearActivity()
        await gateway.disconnect()
        connectionStatus = .disconnected
    }

    // MARK: - Presence

    func handlePlaybackUpdate(
        videoId: String?,
        title: String,
        artist: String,
        album: String?,
        isPlaying: Bool
    ) {
        guard SettingsStore.shared.discordRPCEnabled, isLoggedIn else { return }

        if videoId != lastVideoId || isPlaying != lastIsPlaying {
            throttleTask?.cancel()
            throttleTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await pushNowPlaying(force: false)
            }
        }
    }

    private func pushNowPlaying(force: Bool) async {
        guard SettingsStore.shared.discordRPCEnabled, isLoggedIn else {
            await gateway.clearActivity()
            return
        }

        let np = NowPlaying.shared
        let videoId = np.videoId
        let title = np.title
        let artist = np.displayArtist.isEmpty ? np.artist : np.displayArtist
        let album = np.albumTitle
        let isPlaying = np.isPlaying

        if videoId == nil || title.isEmpty {
            await gateway.clearActivity()
            lastVideoId = nil
            lastIsPlaying = nil
            return
        }

        if !force, videoId == lastVideoId, isPlaying == lastIsPlaying {
            return
        }

        if videoId != lastVideoId {
            activityStartedAt = Int64(Date().timeIntervalSince1970 * 1000)
        }
        lastVideoId = videoId
        lastIsPlaying = isPlaying

        if connectionStatus != .connected {
            await connectIfNeeded()
            guard connectionStatus == .connected else { return }
        }

        let imageURL = videoId.map { NowPlaying.artworkURL(for: $0) }
        let activityName = artist.isEmpty ? "Trop" : artist
        await gateway.updateActivity(
            name: activityName,
            details: title,
            state: artist.isEmpty ? nil : artist,
            largeImageURL: imageURL,
            largeText: album.isEmpty ? title : album,
            startTimestamp: activityStartedAt,
            isPlaying: isPlaying
        )
        Log.discord.debug("Updated presence: \(artist) - \(title) playing=\(isPlaying)")
    }
}
