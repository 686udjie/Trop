//
//  PoTokenGenerator.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import WebKit
import Foundation

actor PoTokenGenerator: NSObject {
    static let shared = PoTokenGenerator()

    private var webView: WKWebView?
    private var webViewReady = false
    private var loadingWebView = false

    private override init() {
        super.init()
    }

    private func ensureWebView() async throws {
        if webViewReady { return }
        if loadingWebView {
            while loadingWebView { try await Task.sleep(nanoseconds: 100_000_000) }
            return
        }

        loadingWebView = true
        defer { loadingWebView = false }

        let wv = try await MainActor.run {
            let handler = PoTokenMessageHandler(generator: self)
            let config = WKWebViewConfiguration()
            let userContent = WKUserContentController()
            userContent.add(handler, name: "botguard")
            config.userContentController = userContent
            config.suppressesIncrementalRendering = true

            guard let htmlPath = Bundle.main.path(forResource: "po_token", ofType: "html"),
                  let html = try? String(contentsOfFile: htmlPath, encoding: .utf8) else {
                throw BotGuardError.invalidResponse
            }

            let w = WKWebView(frame: .zero, configuration: config)
            w.isHidden = true
            w.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
            return w
        }
        self.webView = wv

        try await Task.sleep(nanoseconds: 500_000_000)
        self.webViewReady = true
    }

    func generate(videoId: String, sessionId: String?) async throws -> PoTokenResult {
        try await ensureWebView()

        // 1. Create BotGuard challenge
        print("[PoToken] Creating BotGuard challenge...")
        let challenge = try await BotGuardService.shared.createChallenge()
        print("[PoToken] Challenge: program=\(challenge.program.prefix(50))..."
            + " globalName=\(challenge.globalName ?? "?")"
            + " interpreter=\(challenge.interpreterJavascript != nil)")

        // 2. Build challenge JSON and call runBotGuard in WebView.
        //    The BotGuard JS runs asynchronously; we wait for the Promise.
        //    result.webPoSignalOutput is stored in window.__webPoSignalOutput for later use.
        let challengeJSON = buildChallengeJSON(challenge)
        print("[PoToken] Running BotGuard in WebView...")

        let bgResult = try await evalJS("""
            runBotGuard(\(challengeJSON)).then(function(result) {
                window.__webPoSignalOutput = result.webPoSignalOutput;
                return JSON.stringify({ response: result.botguardResponse });
            })
        """)
        print("[PoToken] BotGuard response received")

        guard let bgData = bgResult.data(using: .utf8),
              let bgObj = try JSONSerialization.jsonObject(with: bgData) as? [String: Any],
              let botguardResponse = bgObj["response"] as? String else {
            throw BotGuardError.descrambleFailed
        }

        // 3. GenerateIT API
        let (integrityTokenU8, _) = try await BotGuardService.shared.generateIT(
            botguardResponse: botguardResponse
        )
        print("[PoToken] Got integrity token")

        // 4. Create poToken minter
        _ = try await evalJS("""
            createPoTokenMinter(window.__webPoSignalOutput, \(integrityTokenU8))
        """)
        print("[PoToken] Minter created")

        // 5. Generate tokens
        let sessionIdStr = sessionId ?? "SESSION"
        let playerToken = try await generatePoToken(sessionIdStr)
        let streamingToken = try await generatePoToken(videoId)

        print("[PoToken] Tokens generated: player=\(playerToken.prefix(30))... stream=\(streamingToken.prefix(30))...")

        return PoTokenResult(
            playerRequestPoToken: playerToken,
            streamingDataPoToken: streamingToken
        )
    }

    private func generatePoToken(_ identifier: String) async throws -> String {
        let idBytes = identifier.data(using: .utf8)!.map { String($0) }.joined(separator: ",")
        let u8id = "new Uint8Array([\(idBytes)])"

        let result = try await evalJS("""
            obtainPoToken(\(u8id))
        """)

        return u8ToBase64(result)
    }

    // MARK: - JS Bridge

    /// Evaluates JS that may return a value (sync or Promise).
    /// The JS must ultimately call postMessage with {id, type, value/error}.
    private func evalJS(_ script: String) async throws -> String {
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            Task { [weak self] in
                guard let self = self else {
                    cont.resume(throwing: BotGuardError.descrambleFailed)
                    return
                }
                await self.setContinuation(id, cont)

                let fullJS = """
                (function() {
                  var __id = "\(id)";
                  try {
                    var __result = \(script);
                    if (__result && typeof __result.then === 'function') {
                      __result.then(
                        function(v) { window.webkit.messageHandlers.botguard.postMessage(
                          JSON.stringify({id:__id, type:'result', value: (v === undefined || v === null) ? '' : String(v) })
                        ); },
                        function(e) { window.webkit.messageHandlers.botguard.postMessage(
                          JSON.stringify({id:__id, type:'error', error: (e && e.message) ? e.message : String(e) })
                        ); }
                      );
                    } else {
                      window.webkit.messageHandlers.botguard.postMessage(
                        JSON.stringify({id:__id, type:'result', value: (__result === undefined || __result === null) ? '' : String(__result) })
                      );
                    }
                  } catch(e) {
                    window.webkit.messageHandlers.botguard.postMessage(
                      JSON.stringify({id:__id, type:'error', error: (e && e.message) ? e.message : String(e) })
                    );
                  }
                })();
                """

                let wv = await self.webView
                await MainActor.run {
                    wv?.evaluateJavaScript(fullJS) { _, error in
                        if error != nil {
                            Task { [weak self] in
                                await self?.resolveContinuation(id, result: .failure(BotGuardError.descrambleFailed))
                            }
                        }
                    }
                }
            }
        }
    }

    private var continuations: [String: CheckedContinuation<String, Error>] = [:]
    private let contQueue = DispatchQueue(label: "potoken.continuations")

    private func setContinuation(_ id: String, _ cont: CheckedContinuation<String, Error>) {
        contQueue.sync { continuations[id] = cont }
    }

    private func resolveContinuation(_ id: String, result: Result<String, Error>) {
        contQueue.sync {
            let cont = continuations.removeValue(forKey: id)
            switch result {
            case .success(let v): cont?.resume(returning: v)
            case .failure(let e): cont?.resume(throwing: e)
            }
        }
    }

    fileprivate func handleMessage(json: [String: Any]) {
        guard let id = json["id"] as? String, let type = json["type"] as? String else { return }

        switch type {
        case "result":
            let value = json["value"] as? String ?? ""
            resolveContinuation(id, result: .success(value))
        case "error":
            let error = json["error"] as? String ?? "Unknown error"
            print("[PoToken] JS error: \(error)")
            resolveContinuation(id, result: .failure(BotGuardError.descrambleFailed))
        default:
            break
        }
    }

    // MARK: - Utilities

    private func buildChallengeJSON(_ challenge: BotGuardChallenge) -> String {
        let interpreterJSON: String
        if let js = challenge.interpreterJavascript {
            let escaped = js.jsEscaped()
            interpreterJSON = """
            {"privateDoNotAccessOrElseSafeScriptWrappedValue":"\(escaped)"}
            """
        } else {
            interpreterJSON = "null"
        }

        let hash = challenge.interpreterHash?.jsEscaped() ?? ""
        let globalName = challenge.globalName?.jsEscaped() ?? ""
        let program = challenge.program.jsEscaped()
        let messageId = challenge.messageId?.jsEscaped() ?? ""

        return """
        {
          "messageId": "\(messageId)",
          "interpreterJavascript": \(interpreterJSON),
          "interpreterHash": "\(hash)",
          "program": "\(program)",
          "globalName": "\(globalName)",
          "clientExperimentsStateBlob": ""
        }
        """
    }

    private func u8ToBase64(_ u8string: String) -> String {
        let bytes = u8string
            .split(separator: ",")
            .compactMap { UInt8($0.trimmingCharacters(in: .whitespaces)) }
        return bytes.isEmpty ? u8string : Data(bytes).base64EncodedString()
    }
}

private extension String {
    func jsEscaped() -> String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

private final class PoTokenMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var generator: PoTokenGenerator?

    init(generator: PoTokenGenerator) {
        self.generator = generator
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "botguard",
              let body = message.body as? String,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        Task { [weak self] in
            await self?.generator?.handleMessage(json: json)
        }
    }
}
