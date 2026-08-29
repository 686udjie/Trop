//
//  DiscordGateway.swift
//  Trop
//

import Foundation

enum DiscordGatewayEvent: Equatable {
    case hello(heartbeatIntervalMs: Int)
    case ready(sessionId: String, resumeURL: String?)
    case resumed
    case invalidSession(resumable: Bool)
    case disconnected(code: Int, reason: String)
}

/// Minimal Discord gateway client for Social Layer presence (IDENTIFY + STATUS_UPDATE).
actor DiscordGateway {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
    }

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatIntervalMs = 41250
    private var sequence: Int?
    private var sessionId: String?
    private var accessToken = ""
    private var applicationId = ""

    private(set) var status: Status = .disconnected
    private var eventHandler: (@Sendable (DiscordGatewayEvent) -> Void)?

    func setEventHandler(_ handler: (@Sendable (DiscordGatewayEvent) -> Void)?) {
        eventHandler = handler
    }

    func connect(token: String, applicationId: String) async {
        await disconnect(emitEvent: false)
        accessToken = token
        self.applicationId = applicationId
        status = .connecting

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)
        self.session = session

        guard let url = URL(string: DiscordDefaults.gatewayURL) else {
            status = .disconnected
            return
        }
        let task = session.webSocketTask(with: url)
        webSocket = task
        task.resume()
        Log.discord.info("Discord gateway connecting")
        receiveTask = Task { await self.receiveLoop() }
    }

    func disconnect(emitEvent: Bool = true) async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        status = .disconnected
        if emitEvent {
            eventHandler?(.disconnected(code: 1000, reason: "local disconnect"))
        }
        Log.discord.info("Discord gateway disconnected")
    }

    func sendPresence(_ payload: [String: Any]) async {
        guard status == .connected, let webSocket else { return }
        await sendJSON(payload, on: webSocket)
    }

    func clearPresence() async {
        await sendPresence(
            DiscordPresence.buildPresenceUpdateJSON(status: .online, activities: [])
        )
    }

    func currentSession() -> (sessionId: String?, seq: Int) {
        (sessionId, sequence ?? 0)
    }

    // MARK: - Internals

    private func receiveLoop() async {
        guard let webSocket else { return }
        while !Task.isCancelled {
            do {
                let message = try await webSocket.receive()
                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    Log.discord.error("Gateway receive error: \(error.localizedDescription)")
                    status = .disconnected
                    eventHandler?(.disconnected(code: 1006, reason: error.localizedDescription))
                }
                break
            }
        }
    }

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let op = json["op"] as? Int else {
            return
        }
        if let s = json["s"] as? Int {
            sequence = s
        }

        switch op {
        case 10:
            if let d = json["d"] as? [String: Any],
               let interval = d["heartbeat_interval"] as? Int {
                heartbeatIntervalMs = interval
            }
            eventHandler?(.hello(heartbeatIntervalMs: heartbeatIntervalMs))
            await sendIdentify()
            startHeartbeat()
        case 11:
            break
        case 0:
            if let t = json["t"] as? String {
                if t == "READY", let d = json["d"] as? [String: Any] {
                    sessionId = d["session_id"] as? String
                    let resume = d["resume_gateway_url"] as? String
                    status = .connected
                    Log.discord.info("Discord gateway READY")
                    eventHandler?(.ready(sessionId: sessionId ?? "", resumeURL: resume))
                } else if t == "RESUMED" {
                    status = .connected
                    eventHandler?(.resumed)
                }
            }
        case 9:
            let resumable = (json["d"] as? Bool) ?? false
            eventHandler?(.invalidSession(resumable: resumable))
        case 7:
            Log.discord.notice("Discord requested reconnect")
            let token = accessToken
            let appId = applicationId
            await connect(token: token, applicationId: appId)
        default:
            break
        }
    }

    private func sendIdentify() async {
        guard let webSocket else { return }
        let payload: [String: Any] = [
            "op": 2,
            "d": [
                "token": accessToken,
                "intents": 0,
                "properties": [
                    "os": "iOS",
                    "browser": "Trop",
                    "device": "Trop"
                ],
                "compress": false,
                "presence": [
                    "status": "online",
                    "since": 0,
                    "activities": [] as [Any],
                    "afk": false
                ]
            ] as [String: Any]
        ]
        await sendJSON(payload, on: webSocket)
    }

    private func sendResume(sessionId: String, seq: Int) async {
        guard let webSocket else { return }
        let payload: [String: Any] = [
            "op": 6,
            "d": [
                "token": accessToken,
                "session_id": sessionId,
                "seq": seq
            ] as [String: Any]
        ]
        await sendJSON(payload, on: webSocket)
    }

    func resumeConnection(sessionId: String, seq: Int, token: String, applicationId: String) async {
        await connect(token: token, applicationId: applicationId)
        // After Hello, identify path runs; override by sending resume once connected path starts.
        // Hello handler always sends identify — for resume we reconnect and let strategy caller
        // use identify with fresh connection. Explicit resume frame after hello is preferred.
        self.sessionId = sessionId
        sequence = seq
        // Wait briefly for hello then resume.
        for _ in 0..<20 {
            if status == .connected || status == .connecting {
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        await sendResume(sessionId: sessionId, seq: seq)
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        let intervalNs = UInt64(max(heartbeatIntervalMs, 1000)) * 1_000_000
        heartbeatTask = Task {
            let jitter = UInt64.random(in: 0..<intervalNs)
            try? await Task.sleep(nanoseconds: jitter)
            while !Task.isCancelled {
                await self.sendHeartbeat()
                try? await Task.sleep(nanoseconds: intervalNs)
            }
        }
    }

    private func sendHeartbeat() async {
        guard let webSocket else { return }
        var d: Any = NSNull()
        if let sequence {
            d = sequence
        }
        await sendJSON(["op": 1, "d": d], on: webSocket)
    }

    private func sendJSON(_ object: [String: Any], on webSocket: URLSessionWebSocketTask) async {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        do {
            try await webSocket.send(.string(text))
        } catch {
            Log.discord.error("Gateway send failed: \(error.localizedDescription)")
        }
    }
}
