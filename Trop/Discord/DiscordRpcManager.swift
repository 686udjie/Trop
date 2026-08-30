//
//  DiscordRpcManager.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import Foundation
import Combine
import UIKit
import OSLog

struct DiscordUser: Equatable {
    let id: String
    let username: String
    let name: String
    let avatar: String?
}

final class DiscordRpcManager: @unchecked Sendable {
    static let shared = DiscordRpcManager()

    enum Status: String { case disconnected, authorizing, connected }

    // MARK: - Published state (mirrors StateFlow)
    private let statusSubject = CurrentValueSubject<Status, Never>(.disconnected)
    var connectionStatus: AnyPublisher<Status, Never> { statusSubject.eraseToAnyPublisher() }
    var connectionStatusValue: Status { statusSubject.value }

    private let lastErrorSubject = CurrentValueSubject<String?, Never>(nil)
    var lastError: AnyPublisher<String?, Never> { lastErrorSubject.eraseToAnyPublisher() }
    var lastErrorValue: String? { lastErrorSubject.value }

    private let currentUserSubject = CurrentValueSubject<DiscordUser?, Never>(nil)
    var currentUser: AnyPublisher<DiscordUser?, Never> { currentUserSubject.eraseToAnyPublisher() }
    var currentUserValue: DiscordUser? { currentUserSubject.value }

    private let accessTokenSubject = CurrentValueSubject<String?, Never>(nil)
    var accessTokenFlow: AnyPublisher<String?, Never> { accessTokenSubject.eraseToAnyPublisher() }

    private let settingsChangedSubject = CurrentValueSubject<Int, Never>(0)
    var settingsChanged: AnyPublisher<Int, Never> { settingsChangedSubject.eraseToAnyPublisher() }

    func notifySettingsChanged() {
        settingsChangedSubject.value += 1
        currentSongId = nil
        currentIsPlaying = false
    }

    // MARK: - Internal state
    private var initialized = false
    private var _ready = false
    private var _authorized = false
    private var accessToken: String?
    private var authorizeInProgress = false
    private var lastActivitySentAtMs: Int64 = 0
    private var lastActivity: ActivityPayload?
    private var currentSongId: String?
    private var currentIsPlaying: Bool = false
    private var currentActivityId: Int64 = 0
    private var currentActivityHadImages: Bool = false
    private var imageResolutionTask: Task<Void, Never>?

    private let auth = DiscordAuth()
    private let appId = DiscordDefaults.appId

    private var gateway: DiscordGateway!
    private var gatewayEventTask: Task<Void, Never>?

    private init() {
        gateway = DiscordGateway(appId: appId, tokenProvider: { [weak self] in
            "Bearer \(self?.accessToken ?? "")"
        })
    }

    private func log(_ msg: String) {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.686udjie.Trop", category: "DiscordSvc").info("\(msg, privacy: .private)")
    }

    // MARK: - Init

    func initializeIfNeeded() {
        guard !initialized else { return }
        initialized = true
        statusSubject.value = .disconnected
        startEventCollection()
        Task {
            if let saved = DiscordTokenStore.shared.retrieve(), !saved.isEmpty {
                reconnectWithToken(saved)
            }
        }
    }

    private func startEventCollection() {
        gatewayEventTask?.cancel()
        gatewayEventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.gateway.events {
                await self.handleGatewayEvent(event)
            }
        }
    }

    // MARK: - Auth

    @MainActor
    func authorize(presentingAnchor: UIWindow? = nil, onComplete: @escaping (Bool) -> Void) {
        if authorizeInProgress { onComplete(false); return }
        if _ready && _authorized { onComplete(true); return }
        if _authorized, let token = accessToken, !token.isEmpty {
            reconnectWithToken(token); onComplete(true); return
        }
        authorizeInProgress = true
        statusSubject.value = .authorizing
        lastErrorSubject.value = nil

        Task { @MainActor in
            do {
                let result = try await auth.authorize(presentingAnchor: presentingAnchor)
                DiscordTokenStore.shared.storeFull(
                    accessToken: result.accessToken, refreshToken: result.refreshToken, expiresInSec: result.expiresInSec)
                self.accessToken = result.accessToken
                self.accessTokenSubject.value = result.accessToken
                self._authorized = true
                do {
                    self.gateway.close(code: 4000, reason: "re-authorizing")
                    // need to ensure gateway is connected then identify
                    try await self.gateway.connect()
                    try await self.gateway.identify(token: "Bearer \(result.accessToken)")
                    onComplete(true)
                } catch {
                    self.lastErrorSubject.value = "discord_error_loopback_timeout"
                    self.statusSubject.value = .disconnected
                    self._ready = false; self._authorized = false
                    onComplete(false)
                }
            } catch let e as DiscordAuthError {
                switch e {
                case .userCancelled: self.lastErrorSubject.value = "discord_error_loopback_timeout"
                case .stateMismatch: self.lastErrorSubject.value = "discord_error_invalid_scope"
                case .noBrowser: self.lastErrorSubject.value = "discord_error_no_browser"
                case .invalidGrant: self.lastErrorSubject.value = "discord_error_token_refresh_failed"
                case .networkFailure: self.lastErrorSubject.value = "discord_error_loopback_timeout"
                case .missingCode: self.lastErrorSubject.value = "discord_error_loopback_timeout"
                }
                self.statusSubject.value = .disconnected
                onComplete(false)
            } catch {
                self.lastErrorSubject.value = "discord_error_loopback_timeout"
                self.statusSubject.value = .disconnected
                onComplete(false)
            }
            self.authorizeInProgress = false
        }
    }

    func cancelAuthorize() { auth.cancel() }

    func handleWebViewAuth(result: DiscordAuthResult) {
        accessToken = result.accessToken
        accessTokenSubject.value = result.accessToken
        _authorized = true
        statusSubject.value = .authorizing
        Task {
            do {
                gateway.close(code: 4000, reason: "re-authorizing")
                try await gateway.connect()
                try await gateway.identify(token: "Bearer \(result.accessToken)")
            } catch {
                lastErrorSubject.value = "discord_error_loopback_timeout"
                statusSubject.value = .disconnected
                _ready = false
                _authorized = false
            }
        }
    }

    func fetchCurrentUserAsync2(token: String) async -> DiscordUser? {
        guard let url = URL(string: "https://discord.com/api/v10/users/@me") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String,
              let username = json["username"] as? String else { return nil }
        let gName = json["global_name"] as? String
        let name = (gName?.isEmpty == false) ? (gName ?? username) : username
        let hash = json["avatar"] as? String
        let avatar: String?
        if let hash, !hash.isEmpty, hash != "null" {
            avatar = "https://cdn.discordapp.com/avatars/\(id)/\(hash).png"
        } else { avatar = nil }
        return DiscordUser(id: id, username: username, name: name, avatar: avatar)
    }

    // MARK: - fetchCurrentUser

    func fetchCurrentUser(token: String) -> DiscordUser? {
        guard let url = URL(string: "https://discord.com/api/v10/users/@me") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        var result: DiscordUser?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, response, _ in
            defer { sem.signal() }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String,
                  let username = json["username"] as? String else { return }
            let gName = json["global_name"] as? String
            let name = (gName?.isEmpty == false) ? (gName ?? username) : username
            let avatarHash = json["avatar"] as? String
            let avatar: String?
            if let hash = avatarHash, !hash.isEmpty, hash != "null" {
                avatar = "https://cdn.discordapp.com/avatars/\(id)/\(hash).png"
            } else { avatar = nil }
            result = DiscordUser(id: id, username: username, name: name, avatar: avatar)
        }.resume()
        sem.wait()
        return result
    }

    // MARK: - setActivity / clear

    func setActivity(activity: DiscordActivity, songId: String?, isPlaying: Bool = true, status: PresenceStatus = .online) {
        guard _ready else { log("setActivity skipping not ready"); return }
        let largeChanged = activity.largeImage != nil
            && activity.largeImage != lastActivity?.largeImage
        let smallChanged = activity.smallImage != nil
            && activity.smallImage != lastActivity?.smallImage
        let stateChanged = songId != currentSongId
            || isPlaying != currentIsPlaying || largeChanged || smallChanged
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if !stateChanged, lastActivitySentAtMs > 0, (now - lastActivitySentAtMs) < 2000 { log("setActivity debounced"); return }
        lastActivitySentAtMs = now
        currentSongId = songId; currentIsPlaying = isPlaying
        currentActivityId &+= 1
        currentActivityHadImages = !(activity.largeImage?.isEmpty ?? true) || !(activity.smallImage?.isEmpty ?? true)

        let buttons: [(String, String)] = {
            var arr: [(String, String)] = []
            if let l = activity.button1Label, !l.isEmpty, let u = activity.button1Url, !u.isEmpty { arr.append((l, u)) }
            if let l = activity.button2Label, !l.isEmpty, let u = activity.button2Url, !u.isEmpty { arr.append((l, u)) }
            return arr
        }()

        let payloadNoImages = DiscordPresence.buildActivity(
            name: activity.name ?? "",
            type: activityTypeToEnum(activity.activityType),
            details: activity.details,
            state: activity.state,
            largeImage: nil, largeText: nil, smallImage: nil, smallText: nil,
            startMs: activity.startTimestamp > 0 ? activity.startTimestamp : nil,
            endMs: activity.endTimestamp,
            buttons: buttons
        )
        lastActivity = payloadNoImages
        do {
            let json = DiscordPresence.buildPresenceUpdate(status: status, activities: [payloadNoImages])
            try gateway.presenceUpdate(json)
        } catch { log("gateway not open") }

        imageResolutionTask?.cancel()
        guard let token = accessToken else { return }
        let largeUrl = activity.largeImage; let smallUrl = activity.smallImage
        if (largeUrl?.isEmpty ?? true) && (smallUrl?.isEmpty ?? true) { return }
        let activityIdAtLaunch = currentActivityId
        imageResolutionTask = Task { [weak self] in
            guard let self else { return }
            let tokenHeader = "Bearer \(token)"
            let largeResolved = largeUrl != nil && !(largeUrl!.isEmpty)
                ? await DiscordExternalAssets.resolve(imageUrl: largeUrl!, appId: self.appId, token: tokenHeader) : nil
            let smallResolved = smallUrl != nil && !(smallUrl!.isEmpty)
                ? await DiscordExternalAssets.resolve(imageUrl: smallUrl!, appId: self.appId, token: tokenHeader) : nil
            if largeResolved == nil && smallResolved == nil { return }
            guard activityIdAtLaunch == self.currentActivityId else { return }
            let payloadWithImages = DiscordPresence.buildActivity(
                name: activity.name ?? "",
                type: self.activityTypeToEnum(activity.activityType),
                details: activity.details, state: activity.state,
                largeImage: largeResolved, largeText: activity.largeText,
                smallImage: smallResolved, smallText: activity.smallText,
                startMs: activity.startTimestamp > 0 ? activity.startTimestamp : nil,
                endMs: activity.endTimestamp,
                buttons: buttons
            )
            self.lastActivity = payloadWithImages
            do {
                let json = DiscordPresence.buildPresenceUpdate(status: status, activities: [payloadWithImages])
                try self.gateway.presenceUpdate(json)
            } catch { self.log("image presence send failed") }
        }
    }

    func clear() {
        guard _ready else { return }
        if lastActivity == nil, currentSongId == nil { return }
        lastActivity = nil; currentSongId = nil; currentIsPlaying = false; currentActivityHadImages = false
        currentActivityId &+= 1; imageResolutionTask?.cancel()
        do {
            let json = DiscordPresence.buildPresenceUpdate(status: .online, activities: [])
            try gateway.presenceUpdate(json)
        } catch {}
    }

    // MARK: - reconnect

    func reconnectWithToken(_ token: String) {
        guard initialized else { return }
        Task {
            // mutex via NSLock quick
            self.accessToken = token
            self.accessTokenSubject.value = token
            DiscordTokenStore.shared.storeAccessToken(token)
            self.statusSubject.value = .authorizing
            // proactive refresh
            let refreshToken = DiscordTokenStore.shared.getRefreshToken()
            let expiresAt = DiscordTokenStore.shared.getExpiresAt()
            let nowSec = Int64(Date().timeIntervalSince1970)
            let needsRefresh = refreshToken != nil && !refreshToken!.isEmpty && expiresAt > 0 && (expiresAt - nowSec) < 3600
            if needsRefresh, let rt = refreshToken {
                do {
                    let refreshed = try await self.auth.refresh(refreshToken: rt)
                    self.accessToken = refreshed.accessToken
                    self.accessTokenSubject.value = refreshed.accessToken
                    DiscordTokenStore.shared.storeFull(
                        accessToken: refreshed.accessToken,
                        refreshToken: refreshed.refreshToken,
                        expiresInSec: refreshed.expiresInSec)
                } catch DiscordAuthError.invalidGrant {
                    self.lastErrorSubject.value = "discord_error_token_refresh_failed"
                    self.logout(); return
                } catch {
                    self.log("refresh failed, continuing with old token: \(error)")
                }
            }
            do {
                self.gateway.close(code: 4000, reason: "reconnecting")
                try await self.gateway.connect()
                try await self.gateway.identify(token: "Bearer \(self.accessToken ?? token)")
            } catch {
                self.lastErrorSubject.value = "discord_error_loopback_timeout"
                self.statusSubject.value = .disconnected
            }
        }
    }

    private func refreshAndReconnect() async {
        guard let rt = DiscordTokenStore.shared.getRefreshToken(), !rt.isEmpty else {
            lastErrorSubject.value = "discord_error_token_refresh_failed"; logout(); return
        }
        do {
            let refreshed = try await auth.refresh(refreshToken: rt)
            DiscordTokenStore.shared.storeFull(
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken,
                expiresInSec: refreshed.expiresInSec)
            reconnectWithToken(refreshed.accessToken)
        } catch DiscordAuthError.invalidGrant {
            lastErrorSubject.value = "discord_error_token_refresh_failed"; logout()
        } catch {
            lastErrorSubject.value = "discord_error_token_refresh_failed"
        }
    }

    // MARK: - disconnect / logout

    func disconnect() {
        currentActivityId &+= 1; imageResolutionTask?.cancel()
        gateway.close(code: 1000, reason: "user disconnect")
        statusSubject.value = .disconnected; _ready = false; _authorized = false
        currentSongId = nil; currentIsPlaying = false; currentActivityHadImages = false
    }

    func destroy() {
        currentActivityId &+= 1; imageResolutionTask?.cancel()
        gateway.close(code: 1000, reason: "destroy")
        gateway.closeHttp()
        gatewayEventTask?.cancel()
        _ready = false; _authorized = false; initialized = false
        statusSubject.value = .disconnected
        lastActivity = nil; currentSongId = nil; currentIsPlaying = false; currentActivityHadImages = false
    }

    func logout() {
        disconnect()
        accessToken = nil; accessTokenSubject.value = nil
        currentUserSubject.value = nil
        DiscordTokenStore.shared.clear()
        DiscordSuperProperties.reset()
        lastErrorSubject.value = nil
        lastActivity = nil; currentActivityHadImages = false
    }

    // MARK: - Helpers

    func isReady() -> Bool { _ready }
    func isAuthorized() -> Bool { _authorized }
    func isInitialized() -> Bool { initialized }
    func getAccessToken() -> String? { accessToken }
    func isShowingSong(songId: String, isPlaying: Bool) -> Bool {
        if currentSongId != songId || currentIsPlaying != isPlaying { return false }
        if lastActivity == nil { return false }
        if currentActivityHadImages, lastActivity?.largeImage == nil, lastActivity?.smallImage == nil,
           imageResolutionTask == nil || imageResolutionTask?.isCancelled == true {
            // still resolving? treat as not shown
            // Actually spec: if hadImages but payload has no images and job done => false
            return false
        }
        return true
    }
    func clearLastError() { lastErrorSubject.value = nil }

    private func activityTypeToEnum(_ code: Int) -> ActivityType {
        switch code {
        case 0: return .playing
        case 1: return .streaming
        case 2: return .listening
        case 3: return .watching
        case 4: return .custom
        case 5: return .competing
        default: return .listening
        }
    }

    private func handleGatewayEvent(_ event: GatewayEvent) async {
        switch event {
        case .ready:
            _ready = true; _authorized = true
            statusSubject.value = .connected; lastErrorSubject.value = nil
            if let token = accessToken {
                Task.detached { [weak self] in
                    guard let self else { return }
                    let user = await self.fetchCurrentUserAsync(token: token)
                    await MainActor.run { self.currentUserSubject.value = user }
                }
            }
        case .resumed:
            _ready = true; _authorized = true
            statusSubject.value = .connected; lastErrorSubject.value = nil
        case .hello, .heartbeatAck, .textDispatch:
            break
        case .disconnected(let code, let reason, _):
            _ready = false; _authorized = false
            statusSubject.value = .disconnected
            currentSongId = nil; currentIsPlaying = false
            imageResolutionTask?.cancel(); imageResolutionTask = nil
            if [4001, 4004].contains(code) && reason.lowercased().contains("max reconnect") {
                if code == 4004 { lastErrorSubject.value = "discord_error_token_refresh_failed" } else if code == 4001 {
                    lastErrorSubject.value = "discord_error_invalid_scope"
                }
            }
            if code == 4014 { lastErrorSubject.value = "discord_error_invalid_scope" }
        case .invalidSession:
            imageResolutionTask?.cancel(); imageResolutionTask = nil
        case .refreshToken:
            await refreshAndReconnect()
        }
    }

    private func fetchCurrentUserAsync(token: String) async -> DiscordUser? {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let u = self.fetchCurrentUser(token: token)
                cont.resume(returning: u)
            }
        }
    }
}
