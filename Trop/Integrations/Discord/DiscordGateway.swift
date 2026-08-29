//
//  DiscordGateway.swift
//  Trop
//

import Foundation

/// Minimal Discord gateway client for classic user-token Rich Presence (STATUS_UPDATE / op 3).
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
    private var heartbeatIntervalMs: Int = 41250
    private var sequence: Int?
    private var token: String = ""
    private var applicationId: String = ""

    private(set) var status: Status = .disconnected

    func connect(token: String, applicationId: String) async {
        await disconnect()
        self.token = token
        self.applicationId = applicationId
        status = .connecting

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)
        self.session = session

        guard let url = URL(string: "wss://gateway.discord.gg/?v=10&encoding=json") else {
            status = .disconnected
            return
        }
        let task = session.webSocketTask(with: url)
        webSocket = task
        task.resume()
        Log.discord.info("Discord gateway connecting")
        receiveTask = Task {
            await self.receiveLoop()
        }
    }

    func disconnect() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        sequence = nil
        status = .disconnected
        Log.discord.info("Discord gateway disconnected")
    }

    func updateActivity(
        name: String,
        details: String?,
        state: String?,
        largeImageURL: String?,
        largeText: String?,
        startTimestamp: Int64?,
        isPlaying: Bool
    ) async {
        guard status == .connected, let webSocket else { return }

        var activity: [String: Any] = [
            "name": name.isEmpty ? "Trop" : name,
            "type": 2,
            "flags": 1
        ]
        if !applicationId.isEmpty {
            activity["application_id"] = applicationId
        }
        if let details, !details.isEmpty { activity["details"] = String(details.prefix(128)) }
        if let state, !state.isEmpty { activity["state"] = String(state.prefix(128)) }

        if let startTimestamp, isPlaying {
            activity["timestamps"] = ["start": startTimestamp]
        }

        var assets: [String: String] = [:]
        if let largeText, !largeText.isEmpty {
            assets["large_text"] = String(largeText.prefix(128))
        }
        if let largeImageURL, !largeImageURL.isEmpty {
            // External media proxy prefix used by classic music RPC clients.
            assets["large_image"] = "mp:\(largeImageURL)"
        }
        if !assets.isEmpty {
            activity["assets"] = assets
        }

        let payload: [String: Any] = [
            "op": 3,
            "d": [
                "since": NSNull(),
                "activities": isPlaying || details != nil ? [activity] : [],
                "status": isPlaying ? "online" : "idle",
                "afk": false
            ] as [String: Any]
        ]
        await sendJSON(payload, on: webSocket)
    }

    func clearActivity() async {
        guard status == .connected, let webSocket else { return }
        let payload: [String: Any] = [
            "op": 3,
            "d": [
                "since": NSNull(),
                "activities": [] as [Any],
                "status": "online",
                "afk": false
            ] as [String: Any]
        ]
        await sendJSON(payload, on: webSocket)
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
            // Hello
            if let d = json["d"] as? [String: Any],
               let interval = d["heartbeat_interval"] as? Int {
                heartbeatIntervalMs = interval
            }
            await sendIdentify()
            startHeartbeat()
        case 11:
            // Heartbeat ACK
            break
        case 0:
            if let t = json["t"] as? String, t == "READY" {
                status = .connected
                Log.discord.info("Discord gateway READY")
            }
        case 9:
            Log.discord.error("Discord invalid session")
            status = .disconnected
            await disconnect()
        case 7:
            Log.discord.notice("Discord requested reconnect")
            let token = self.token
            let appId = self.applicationId
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
                "token": token,
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
