//
//  DiscordGateway.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import Foundation
import OSLog

private let defaultGatewayUrl = DiscordDefaults.gatewayUrl
private let defaultHeartbeatMs: Int64 = 41_250
private let jitterRatio: Double = 0.05
private let maxReconnectAttempts = 7
private let reconnectBaseDelayMs: Int64 = 1_000
private let reconnectMaxDelayMs: Int64 = 64_000

private enum GatewayOp: Int {
    case dispatch = 0, heartbeat = 1, identify = 2, presenceUpdate = 3
    case voiceState = 4, resume = 6, reconnect = 7, invalidSession = 9
    case hello = 10, heartbeatAck = 11
}

enum GatewayEvent: @unchecked Sendable {
    case hello(heartbeatIntervalMs: Int64)
    case ready(sessionId: String, resumeGatewayUrl: String?)
    case resumed(sessionId: String)
    case heartbeatAck(lastSeq: Int?)
    case invalidSession(resumable: Bool)
    case disconnected(code: Int, reason: String, remote: Bool)
    case refreshToken
    case textDispatch(op: Int, t: String?, d: [String: Any])
}

final class DiscordGateway: @unchecked Sendable {
    private let appId: String
    private let tokenProvider: @Sendable () async -> String
    private var gatewayUrl = defaultGatewayUrl
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.686udjie.Trop", category: "DiscordGateway")

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession = .shared
    private lazy var sessionWithDelegate: URLSession = URLSession(configuration: .default, delegate: delegateHandler, delegateQueue: nil)
    private let delegateHandler = GatewayDelegate()
    private var isOpen = false
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var lastAckAtMs: Int64 = 0
    private var currentSeq: Int = 0
    private var _sessionId: String?
    var sessionId: String? { _sessionId }
    var seq: Int { currentSeq }
    private var reconnectAttempts = 0
    private var activeId: Int64 = 0
    private var idCounter: Int64 = 0

    // Events — use AsyncStream + Combine? Simple AsyncStream
    private var eventContinuation: AsyncStream<GatewayEvent>.Continuation?
    let events: AsyncStream<GatewayEvent>

    init(appId: String, tokenProvider: @escaping @Sendable () async -> String) {
        self.appId = appId
        self.tokenProvider = tokenProvider
        var cont: AsyncStream<GatewayEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { c in cont = c }
        self.eventContinuation = cont
    }

    private func emit(_ event: GatewayEvent) {
        eventContinuation?.yield(event)
    }

    // MARK: - Public API

    func setGatewayUrl(_ url: String) { gatewayUrl = url }

    func connect() async throws {
        idCounter += 1
        let myId = idCounter
        activeId = myId
        guard let url = URL(string: gatewayUrl) else { throw URLError(.badURL) }
        let task = sessionWithDelegate.webSocketTask(with: url)
        webSocketTask = task
        isOpen = false
        task.resume()
        startReceiveLoop(myId: myId)
        try await Task.sleep(nanoseconds: 200_000_000)
        guard activeId == myId, webSocketTask != nil else { throw URLError(.cannotConnectToHost) }
        isOpen = true
        lastAckAtMs = nowMs()
    }

    func close(code: Int = 1000, reason: String? = nil) {
        heartbeatTask?.cancel(); heartbeatTask = nil
        receiveTask?.cancel(); receiveTask = nil
        let task = webSocketTask; webSocketTask = nil
        isOpen = false
        idCounter += 1 // invalidate old
        if let task = task {
            task.cancel(with: .goingAway, reason: reason?.data(using: .utf8))
        }
    }

    func closeHttp() {
        // URLSession.shared doesn't need close
        close()
    }

    func send(_ json: String) throws {
        guard let task = webSocketTask, isOpen else {
            throw NSError(domain: "DiscordGateway", code: -1, userInfo: [NSLocalizedDescriptionKey: "WebSocket not open"])
        }
        Task { try? await task.send(.string(json)) }
    }

    func identify(token: String) async throws {
        try send(buildIdentifyFrame(token: token))
    }

    func presenceUpdate(_ presenceJson: String) throws {
        try send(presenceJson)
    }

    func resume(sessionId: String, seq: Int, token: String) async throws {
        try send(buildResumeFrame(sessionId: sessionId, seq: seq, token: token))
    }

    func heartbeat(seq: Int) throws {
        try send(buildHeartbeatFrame(seq: seq))
    }

    // MARK: - Frames

    private func buildIdentifyFrame(token: String) -> String {
        let d: [String: Any] = [
            "token": token,
            "intents": 0,
            "properties": ["os": "android", "browser": "Discord Android", "device": appId],
            "compress": false
        ]
        return wrapOp(2, d: d)
    }

    private func buildResumeFrame(sessionId: String, seq: Int, token: String) -> String {
        let d: [String: Any] = ["token": token, "session_id": sessionId, "seq": seq]
        return wrapOp(6, d: d)
    }

    private func buildHeartbeatFrame(seq: Int) -> String {
        var root: [String: Any] = ["op": GatewayOp.heartbeat.rawValue]
        if seq > 0 { root["d"] = seq } else { root["d"] = NSNull() }
        return jsonString(root)
    }

    private func wrapOp(_ op: Int, d: [String: Any]) -> String {
        jsonString(["op": op, "d": d])
    }

    private func jsonString(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    // MARK: - Receive loop

    private func startReceiveLoop(myId: Int64) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let task = self.webSocketTask, self.activeId == myId else { return }
                do {
                    let msg = try await task.receive()
                    switch msg {
                    case .string(let text):
                        self.handleFrame(text)
                    case .data:
                        break
                    @unknown default: break
                    }
                } catch {
                    await self.handleClose(code: 4000, reason: error.localizedDescription, remote: false, wsId: myId)
                    return
                }
            }
        }
    }

    private func handleFrame(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let op = json["op"] as? Int ?? -1
        let dAny = json["d"]
        let dDict = dAny as? [String: Any]
        let t = json["t"] as? String
        if let s = json["s"] as? Int, s > 0 { currentSeq = s } else if let s = json["s"] as? NSNumber,
                                                                             s.intValue > 0 { currentSeq = s.intValue }

        switch op {
        case GatewayOp.hello.rawValue:
            let interval = (dDict?["heartbeat_interval"] as? NSNumber)?.int64Value
                ?? (dDict?["heartbeat_interval"] as? Int64)
                ?? defaultHeartbeatMs
            startHeartbeat(intervalMs: interval)
            emit(.hello(heartbeatIntervalMs: interval))
        case GatewayOp.heartbeatAck.rawValue:
            lastAckAtMs = nowMs()
            emit(.heartbeatAck(lastSeq: self.currentSeq))
        case GatewayOp.dispatch.rawValue:
            if t == "READY" {
                let sid = dDict?["session_id"] as? String ?? ""
                let resumeUrl = (dDict?["resume_gateway_url"] as? String)?.nilIfEmpty
                _sessionId = sid
                if let ru = resumeUrl { setGatewayUrl(ru) }
                reconnectAttempts = 0
                emit(.ready(sessionId: sid, resumeGatewayUrl: resumeUrl))
            } else if t == "RESUMED" {
                reconnectAttempts = 0
                emit(.resumed(sessionId: _sessionId ?? ""))
            } else {
                emit(.textDispatch(op: op, t: t, d: dDict ?? [:]))
            }
        case GatewayOp.invalidSession.rawValue:
            let resumable = (json["d"] as? Bool) ?? false
            if !resumable { _sessionId = nil }
            emit(.invalidSession(resumable: resumable))
            Task { await self.handleClose(code: 4000, reason: "invalid session", remote: true, wsId: activeId) }
        case GatewayOp.heartbeat.rawValue:
            try? heartbeat(seq: currentSeq)
        case GatewayOp.reconnect.rawValue:
            Task { await self.handleClose(code: 4000, reason: "reconnect requested", remote: true, wsId: activeId) }
        default:
            emit(.textDispatch(op: op, t: t, d: dDict ?? [:]))
        }
    }

    private func handleClose(code: Int, reason: String, remote: Bool, wsId: Int64) async {
        log.warning("Gateway CLOSE code=\(code, privacy: .public) reason=\(reason, privacy: .private) remote=\(remote, privacy: .public)")
        guard wsId == activeId else { return }
        if !isOpen, webSocketTask == nil { return }
        isOpen = false
        heartbeatTask?.cancel(); heartbeatTask = nil
        webSocketTask = nil
        emit(.disconnected(code: code, reason: reason, remote: remote))

        if code == 1000, remote { _sessionId = nil; currentSeq = 0; return }

        let action = DiscordReconnectStrategy.decide(closeCode: code, hadSession: _sessionId != nil, seq: currentSeq, sessionId: _sessionId)
        switch action {
        case .surfaceFatal:
            _sessionId = nil; currentSeq = 0
        case .refreshAndReIdentify:
            emit(.refreshToken)
        case .resume, .reIdentify:
            if reconnectAttempts >= maxReconnectAttempts {
                emit(.disconnected(code: 4000, reason: "max reconnect attempts", remote: false))
                return
            }
            reconnectAttempts += 1
            let delayMs: Int64
            if code == 429 {
                delayMs = max(parseRetryAfter(reason), 60_000)
            } else {
                delayMs = reconnectDelayMs(attempt: reconnectAttempts)
            }
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            await performReconnect(action: action)
        }
    }

    private func performReconnect(action: ReconnectAction) async {
        do { try await connect() } catch { return }
        switch action {
        case .resume(let sid, let seq):
            let token = await tokenProvider()
            try? await resume(sessionId: sid, seq: seq, token: token)
        case .reIdentify:
            let token = await tokenProvider()
            try? await identify(token: token)
        default: break
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat(intervalMs: Int64) {
        heartbeatTask?.cancel()
        let jittered = applyJitter(intervalMs, ratio: jitterRatio)
        lastAckAtMs = nowMs()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            var lastSentAt = self.nowMs()
            while !Task.isCancelled, self.isOpen {
                try? await Task.sleep(nanoseconds: UInt64(jittered) * 1_000_000)
                guard !Task.isCancelled, self.isOpen else { break }
                let lastAck = self.lastAckAtMs
                if lastAck < lastSentAt {
                    await self.handleClose(code: 4000, reason: "heartbeat timeout", remote: false, wsId: self.activeId)
                    break
                }
                lastSentAt = self.nowMs()
                try? self.heartbeat(seq: self.currentSeq)
            }
        }
    }

    private func applyJitter(_ interval: Int64, ratio: Double) -> Int64 {
        let delta = Int64(Double(interval) * ratio)
        guard delta > 0 else { return interval }
        let offset = Int64.random(in: 0...delta)
        let sign = Bool.random() ? 1 : -1
        return interval + Int64(sign) * offset
    }

    private func reconnectDelayMs(attempt: Int) -> Int64 {
        let base = min(reconnectBaseDelayMs * Int64(1 << (attempt - 1)), reconnectMaxDelayMs)
        return applyJitter(base, ratio: 0.25)
    }

    private func parseRetryAfter(_ reason: String) -> Int64 {
        guard let range = reason.range(of: ";retry_after=") else { return 60_000 }
        let after = reason[range.upperBound...]
        let numStr = after.prefix(while: { $0.isNumber || $0 == "." })
        if let d = Double(numStr) { return Int64(d * 1000) }
        return 60_000
    }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

private final class GatewayDelegate: NSObject, URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        if closeCode != .normalClosure {
            let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "nil"
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.686udjie.Trop", category: "DiscordGateway")
                .warning("WebSocket didClose code=\(closeCode.rawValue, privacy: .public) reason=\(reasonStr, privacy: .private)")
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
