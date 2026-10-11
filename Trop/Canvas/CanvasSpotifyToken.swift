//
//  CanvasSpotifyToken.swift
//  Trop
//
//  Created by 686udjie on 11/10/2026.
//

import Foundation
import UIKit
import WebKit

/// Minted credentials for the Spotify web-player endpoints.
struct HarvestedCanvasToken {
    let token: String
    let expiresAt: Date
    let clientId: String?
}

actor CanvasSpotifyToken {
    static let shared = CanvasSpotifyToken()

    static let harvestTimeoutSeconds: UInt64 = 20
    static let tokenLifetimeFallback: TimeInterval = 3600
    private static let refreshLeeway: TimeInterval = 30

    private var cachedToken: HarvestedCanvasToken?
    private var cachedClientToken: String?
    private var cachedClientId: String?
    private var harvestGeneration = 0
    private var clientTokenExpiresAt = Date.distantPast
    private var cachedSession: CanvasSessionInfo?
    private var harvestInFlight = false

    func accessToken() async -> String? {
        guard let cookie = SpotifyAccountStore.shared.cookie(), !cookie.isEmpty else { return nil }
        return await harvestedToken(cookie: cookie)?.token
    }

    func seed(_ token: HarvestedCanvasToken) {
        harvestGeneration += 1
        cachedToken = token
    }

    func harvestedToken(cookie: String) async -> HarvestedCanvasToken? {
        if let cached = cachedToken, cached.expiresAt.timeIntervalSinceNow > Self.refreshLeeway {
            return cached
        }
        guard !harvestInFlight else { return cachedToken }
        harvestInFlight = true
        defer { harvestInFlight = false }
        let generation = harvestGeneration
        guard let harvested = await harvest(cookie: cookie) else { return cachedToken }
        guard generation == harvestGeneration else { return cachedToken }
        cachedToken = harvested
        return harvested
    }

    func clientToken() async -> String? {
        guard let clientId = cachedToken?.clientId else { return nil }
        return await clientToken(clientId: clientId)
    }

    func clientToken(clientId: String) async -> String? {
        if let cached = cachedClientToken, cachedClientId == clientId,
           clientTokenExpiresAt.timeIntervalSinceNow > Self.refreshLeeway {
            return cached
        }
        guard let session = await sessionInfo() else {
            return nil
        }
        guard let minted = await mintClientToken(clientId: clientId, session: session) else {
            return nil
        }
        cachedClientId = clientId
        cachedClientToken = minted.token
        clientTokenExpiresAt = Date().addingTimeInterval(minted.ttl)
        return minted.token
    }

    /// Drops everything; call when the cookie changes or on logout. Retires
    /// any harvest still running for the old session.
    func invalidate() {
        harvestGeneration += 1
        cachedToken = nil
        cachedClientToken = nil
        cachedClientId = nil
        clientTokenExpiresAt = .distantPast
    }

    // MARK: - Harvest

    private func harvest(cookie: String) async -> HarvestedCanvasToken? {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                CanvasTokenHarvester(cookie: cookie, continuation: continuation).start()
            }
        }
    }

    // MARK: - Client token + session

    private func mintClientToken(clientId: String, session: CanvasSessionInfo) async -> (token: String, ttl: TimeInterval)? {
        let osVersion = await MainActor.run { UIDevice.current.systemVersion }
        let payload: [String: Any] = [
            "client_data": [
                "client_version": session.clientVersion,
                "client_id": clientId,
                "js_sdk_data": [
                    "device_brand": "unknown",
                    "device_model": "unknown",
                    "os": "ios",
                    "os_version": osVersion,
                    "device_id": session.deviceId,
                    "device_type": "smartphone"
                ]
            ]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        var request = URLRequest(url: URL(string: "https://clienttoken.spotify.com/v1/clienttoken")!)
        request.httpMethod = "POST"
        request.httpBody = body
        // Bare media type, deliberately: the charset-suffixed variant is rejected.
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(CanvasEndpoints.webUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["response_type"] as? String == "RESPONSE_GRANTED_TOKEN_RESPONSE",
              let granted = json["granted_token"] as? [String: Any],
              let token = granted["token"] as? String
        else { return nil }
        let ttl = (granted["expires_after_seconds"] as? NSNumber)?.doubleValue ?? Self.tokenLifetimeFallback
        return (token, ttl)
    }

    private func sessionInfo() async -> CanvasSessionInfo? {
        if let cached = cachedSession { return cached }
        var request = URLRequest(url: URL(string: "https://open.spotify.com/")!)
        request.setValue(CanvasEndpoints.webUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8)
        else { return nil }
        let deviceId: String = {
            guard let http = response as? HTTPURLResponse else { return UUID().uuidString }
            for (key, value) in http.allHeaderFields {
                guard (key as? String)?.lowercased() == "set-cookie", let cookie = value as? String else { continue }
                if let match = cookie.range(of: "sp_t=([^;]+)", options: .regularExpression) {
                    return String(cookie[match]).replacingOccurrences(of: "sp_t=", with: "")
                }
            }
            return UUID().uuidString
        }()
        guard let configRange = html.range(of: "<script id=\"appServerConfig\" type=\"text/plain\">([^<]+)</script>",
                                           options: .regularExpression),
              let payload = CanvasSpotifyToken.decodeConfig(String(html[configRange])),
              let version = payload["clientVersion"] as? String
        else { return nil }
        let session = CanvasSessionInfo(clientVersion: version, deviceId: deviceId)
        cachedSession = session
        return session
    }

    private static func decodeConfig(_ scriptTag: String) -> [String: Any]? {
        guard let start = scriptTag.firstIndex(of: ">"), let end = scriptTag.lastIndex(of: "<"),
              start < end,
              let payload = Data(base64Encoded: String(scriptTag[scriptTag.index(after: start)..<end])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return nil }
        return json
    }
}

private struct CanvasSessionInfo {
    let clientVersion: String
    let deviceId: String
}

// MARK: - Offscreen harvest

/// The `/api/token` hook shared by the offscreen harvester and the login
/// webview: injected before the player bundle runs, it reports the raw token
/// payloads the page mints for itself over a message bridge.
enum CanvasTokenHook {
    static let bridgeName = "tropCanvasToken"

    /// Parses a hooked payload into a bearer, or nil for anonymous tokens
    /// (minted before the session applies — those can't read canvases).
    static func parse(_ payload: String) -> HarvestedCanvasToken? {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["accessToken"] as? String, !token.isEmpty,
              (json["isAnonymous"] as? Bool) != true
        else { return nil }
        let expiresAt: Date = {
            if let ms = (json["accessTokenExpirationTimestampMs"] as? NSNumber)?.doubleValue,
               ms / 1000 > Date().timeIntervalSince1970 {
                return Date(timeIntervalSince1970: ms / 1000)
            }
            return Date().addingTimeInterval(CanvasSpotifyToken.tokenLifetimeFallback)
        }()
        return HarvestedCanvasToken(token: token, expiresAt: expiresAt, clientId: json["clientId"] as? String)
    }

    static let script = """
        (function () {
          if (window.__tropCanvasHook) return;
          window.__tropCanvasHook = true;
          var report = function (body) {
            try { window.webkit.messageHandlers.tropCanvasToken.postMessage(body); } catch (e) {}
          };
          var isToken = function (u) {
            try { return String(u).indexOf('/api/token') !== -1; } catch (e) { return false; }
          };
          var origFetch = window.fetch;
          if (origFetch) {
            window.fetch = function (input, init) {
              var url = (input && input.url) ? input.url : input;
              var result = origFetch.apply(this, arguments);
              if (isToken(url)) {
                try {
                  result.then(function (res) {
                    res.clone().text().then(report).catch(function () {});
                  }).catch(function () {});
                } catch (e) {}
              }
              return result;
            };
          }
          var origOpen = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function (method, url) {
            this.__tropCanvasUrl = url;
            return origOpen.apply(this, arguments);
          };
          var origSend = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.send = function () {
            var xhr = this;
            try {
              xhr.addEventListener('load', function () {
                if (isToken(xhr.__tropCanvasUrl)) {
                  try { report(xhr.responseText); } catch (e) {}
                }
              });
            } catch (e) {}
            return origSend.apply(this, arguments);
          };
        })();
        """
}

/// Loads the real web player offscreen with the cookie applied and captures
/// the `/api/token` payload it mints for itself. Main-actor bound: WKWebView
/// must live and die on the main thread.
@MainActor
private final class CanvasTokenHarvester: NSObject, WKScriptMessageHandler {
    private let cookie: String
    private var continuation: CheckedContinuation<HarvestedCanvasToken?, Never>?
    private var webView: WKWebView?
    private var finished = false

    init(cookie: String, continuation: CheckedContinuation<HarvestedCanvasToken?, Never>) {
        self.cookie = cookie
        self.continuation = continuation
    }

    func start() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(self, name: CanvasTokenHook.bridgeName)
        config.userContentController.addUserScript(
            WKUserScript(source: CanvasTokenHook.script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        let webView = WKWebView(frame: .zero, configuration: config)
        self.webView = webView
        let spDc: [HTTPCookiePropertyKey: Any] = [
            .name: "sp_dc", .value: cookie, .domain: ".spotify.com", .path: "/",
            .secure: true, .expires: Date().addingTimeInterval(3600)
        ]
        guard let httpCookie = HTTPCookie(properties: spDc) else {
            finish(nil)
            return
        }
        config.websiteDataStore.httpCookieStore.setCookie(httpCookie) { [weak self] in
            self?.webView?.load(URLRequest(url: URL(string: "https://open.spotify.com/")!))
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: CanvasSpotifyToken.harvestTimeoutSeconds * 1_000_000_000)
            self?.finish(nil)
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let payload = message.body as? String,
              let harvested = CanvasTokenHook.parse(payload)
        else { return }
        finish(harvested)
    }

    private func finish(_ token: HarvestedCanvasToken?) {
        guard !finished else { return }
        finished = true
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: CanvasTokenHook.bridgeName)
        webView?.stopLoading()
        webView = nil
        continuation?.resume(returning: token)
        continuation = nil
    }
}
