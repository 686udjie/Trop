//
//  DiscordRpcManager.swift
//  Trop
//

import Foundation

struct DiscordUserInfo: Equatable {
    var id: String?
    var username: String?
}

/// Singleton Discord Rich Presence manager (PKCE auth + gateway STATUS_UPDATE).
@MainActor
@Observable
final class DiscordRpcManager {
    static let shared = DiscordRpcManager()

    enum ConnectionStatus: String {
        case disconnected = "Disconnected"
        case authorizing = "Authorizing"
        case connecting = "Connecting"
        case connected = "Connected"
    }

    private(set) var clientId = ""
    private(set) var connectionStatus: ConnectionStatus = .disconnected
    private(set) var lastError: String?
    private(set) var currentUser: DiscordUserInfo?
    private(set) var isAuthorized = false

    private let gateway = DiscordGateway()
    private var tokens: DiscordTokenStore.Tokens?
    private var lastVideoId: String?
    private var lastIsPlaying: Bool?
    private var activityStartedAt: Int64?
    private var throttleTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    private init() {
        tokens = DiscordTokenStore.load()
        isAuthorized = tokens?.hasAccessToken == true
        currentUser = DiscordUserInfo(id: tokens?.userId, username: tokens?.username)
    }

    var username: String? { currentUser?.username }

    func initialize(clientId: String) {
        self.clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.discord.info("DiscordRpcManager initialized (clientId present=\(!self.clientId.isEmpty))")
    }

    func authorize() async throws {
        guard !clientId.isEmpty else { throw DiscordAuthError.missingClientId }
        connectionStatus = .authorizing
        lastError = nil
        do {
            let result = try await DiscordAuth.authorize(clientId: clientId)
            try persist(result)
            connectionStatus = .disconnected
            if SettingsStore.shared.discordRPCEnabled {
                await connectIfAuthorized()
            }
        } catch {
            connectionStatus = .disconnected
            lastError = error.localizedDescription
            throw error
        }
    }

    func connectIfAuthorized() async {
        guard SettingsStore.shared.discordRPCEnabled else {
            await gateway.disconnect()
            connectionStatus = .disconnected
            return
        }
        guard var tokens, tokens.hasAccessToken else {
            connectionStatus = .disconnected
            return
        }
        if tokens.isExpired, !tokens.refreshToken.isEmpty {
            do {
                let refreshed = try await DiscordAuth.refresh(
                    refreshToken: tokens.refreshToken,
                    clientId: clientId
                )
                try persist(refreshed)
                tokens = self.tokens!
            } catch {
                lastError = error.localizedDescription
                connectionStatus = .disconnected
                return
            }
        }

        connectionStatus = .connecting
        await gateway.setEventHandler { [weak self] event in
            Task { @MainActor in
                await self?.handleGatewayEvent(event)
            }
        }
        await gateway.connect(token: tokens.accessToken, applicationId: clientId)

        for _ in 0..<40 {
            if await gateway.status == .connected {
                connectionStatus = .connected
                lastError = nil
                await pushNowPlaying(force: true)
                return
            }
            if await gateway.status == .disconnected {
                break
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if connectionStatus != .connected {
            connectionStatus = .disconnected
            lastError = lastError ?? "Could not connect to Discord gateway"
        }
    }

    func disconnect() async {
        await gateway.clearPresence()
        await gateway.disconnect()
        connectionStatus = .disconnected
    }

    func logout() async {
        try? DiscordTokenStore.clear()
        tokens = nil
        isAuthorized = false
        currentUser = nil
        await disconnect()
        lastError = nil
        Log.discord.info("Logged out of Discord")
    }

    func setActivity(
        videoId: String?,
        title: String,
        artist: String,
        album: String?,
        isPlaying: Bool
    ) {
        guard SettingsStore.shared.discordRPCEnabled, isAuthorized else { return }
        if videoId != lastVideoId || isPlaying != lastIsPlaying {
            throttleTask?.cancel()
            throttleTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await pushNowPlaying(force: false)
            }
        }
    }

    func clear() async {
        await gateway.clearPresence()
        lastVideoId = nil
        lastIsPlaying = nil
    }

    // MARK: - Private

    private func persist(_ result: DiscordAuthResult) throws {
        let expiresAt: TimeInterval
        if result.expiresInSec > 0 {
            expiresAt = Date().timeIntervalSince1970 + TimeInterval(result.expiresInSec)
        } else {
            expiresAt = 0
        }
        let stored = DiscordTokenStore.Tokens(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAt: expiresAt,
            username: tokens?.username,
            userId: tokens?.userId
        )
        try DiscordTokenStore.save(stored)
        tokens = stored
        isAuthorized = true
        Log.discord.info("Saved Discord OAuth tokens")
    }

    private func handleGatewayEvent(_ event: DiscordGatewayEvent) async {
        switch event {
        case .ready, .resumed:
            connectionStatus = .connected
        case .disconnected(let code, _):
            connectionStatus = .disconnected
            await handleDisconnect(code: code)
        case .invalidSession:
            connectionStatus = .disconnected
            await connectIfAuthorized()
        case .hello:
            break
        }
    }

    private func handleDisconnect(code: Int) async {
        reconnectTask?.cancel()
        reconnectTask = Task {
            let session = await gateway.currentSession()
            let action = DiscordReconnectStrategy.decide(
                closeCode: code,
                hadSession: session.sessionId != nil,
                seq: session.seq,
                sessionId: session.sessionId
            )
            switch action {
            case .resume(let sessionId, let seq):
                guard let token = tokens?.accessToken else { return }
                await gateway.resumeConnection(
                    sessionId: sessionId,
                    seq: seq,
                    token: token,
                    applicationId: clientId
                )
            case .reIdentify:
                await connectIfAuthorized()
            case .refreshAndReIdentify:
                guard let refresh = tokens?.refreshToken, !refresh.isEmpty else {
                    lastError = "Discord session expired — sign in again"
                    return
                }
                do {
                    let refreshed = try await DiscordAuth.refresh(
                        refreshToken: refresh,
                        clientId: clientId
                    )
                    try persist(refreshed)
                    await connectIfAuthorized()
                } catch {
                    lastError = error.localizedDescription
                }
            case .surfaceFatal:
                lastError = "Discord rejected the connection (\(code))"
            }
        }
    }

    private func pushNowPlaying(force: Bool) async {
        guard SettingsStore.shared.discordRPCEnabled, isAuthorized else {
            await gateway.clearPresence()
            return
        }

        let np = NowPlaying.shared
        let videoId = np.videoId
        let title = np.title
        let artist = np.displayArtist.isEmpty ? np.artist : np.displayArtist
        let album = np.albumTitle
        let isPlaying = np.isPlaying

        if videoId == nil || title.isEmpty {
            await gateway.clearPresence()
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
            await connectIfAuthorized()
            guard connectionStatus == .connected else { return }
        }

        var largeImage: String?
        if let videoId, let token = tokens?.accessToken {
            let artwork = NowPlaying.artworkURL(for: videoId)
            largeImage = await DiscordExternalAssets.shared.resolve(
                imageURL: artwork,
                appId: clientId,
                accessToken: token
            )
        }

        var buttons: [(String, String)] = []
        if let videoId {
            buttons.append((
                DiscordDefaults.button1Label,
                DiscordDefaults.youtubeWatchURL + videoId
            ))
        }
        buttons.append((DiscordDefaults.button2Label, DiscordDefaults.button2URL))

        let activity = DiscordPresence.buildActivity(
            name: artist.isEmpty ? "Trop" : artist,
            details: title,
            state: artist.isEmpty ? DiscordDefaults.unknownArtist : artist,
            largeImage: largeImage,
            largeText: album.isEmpty ? title : album,
            startMs: isPlaying ? activityStartedAt : nil,
            buttons: buttons
        )

        let payload = DiscordPresence.buildPresenceUpdateJSON(
            status: isPlaying ? .online : .idle,
            activities: isPlaying || !title.isEmpty ? [activity] : []
        )
        await gateway.sendPresence(payload)
        Log.discord.debug("Updated presence: \(artist) - \(title) playing=\(isPlaying)")
    }
}
