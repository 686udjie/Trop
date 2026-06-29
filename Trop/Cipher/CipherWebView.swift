//
//  CipherWebView.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import WebKit
import Foundation

actor CipherWebView: NSObject {
    static let shared = CipherWebView()

    private var isReady = false
    private var playerHash: String?
    private var readyContinuation: CheckedContinuation<Void, Error>?

    private var webView: WKWebView?

    private var playerDir: URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let trop = documents?.appendingPathComponent("Trop", isDirectory: true)
        let player = trop?.appendingPathComponent("Player", isDirectory: true)
        return player
    }

    private override init() {
        super.init()
    }

    func load() async throws {
        let hash = try await PlayerJsFetcher.shared.getPlayerHash()

        if isReady, self.playerHash == hash {
            return
        }
        self.playerHash = hash

        let playerJs = try await PlayerJsFetcher.shared.getPlayerJs()

        let sigConfig: String?
        let nClass: String?
        if let config = await PlayerConfigStore.shared.config(for: hash) {
            sigConfig = config.sigFunction.body
            nClass = config.nFunction.varName
            print("[CipherWebView] Config found: sig=\(sigConfig ?? "?"), nClass=\(nClass ?? "?")")
        } else {
            sigConfig = nil
            nClass = nil
            print("[CipherWebView] No config for hash \(hash)")
        }

        // Patch player.js to expose cipher functions on window
        let patchedJs = CipherHTMLBuilder.patchPlayerJs(
            playerJs: playerJs,
            sigConfig: sigConfig,
            nClass: nClass,
            playerHash: hash
        )

        // Save patched player.js to local file
        guard let dir = playerDir else { throw CipherError.cacheUnavailable }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        print("[CipherWebView] Player directory: \(dir.path)")
        let playerFile = dir.appendingPathComponent("base_\(hash).js")
        try patchedJs.write(to: playerFile, atomically: true, encoding: .utf8)

        // Generate file-based HTML
        let html = CipherHTMLBuilder.buildFileBasedHTML(playerHash: hash)

        // Save HTML to temp file in same directory
        let htmlFile = dir.appendingPathComponent("cipher_\(hash).html")
        try html.write(to: htmlFile, atomically: true, encoding: .utf8)

        let wv: WKWebView = await MainActor.run {
            let handler = CipherMessageHandler(cipher: self)
            let config = WKWebViewConfiguration()
            let userContent = WKUserContentController()
            userContent.add(handler, name: "cipher")
            config.userContentController = userContent
            config.suppressesIncrementalRendering = true

            let w = WKWebView(frame: .zero, configuration: config)
            w.isHidden = true
            w.loadFileURL(htmlFile, allowingReadAccessTo: dir)
            return w
        }
        self.webView = wv

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.readyContinuation = cont
        }

        self.isReady = true
        print("[CipherWebView] Ready (file-based, hash=\(hash))")
    }

    func resolveCipherURL(cipherText: String) async throws -> String {
        let params = parseQueryString(cipherText)
        guard let urlParam = params["url"] else {
            throw CipherError.invalidResponse("No url in cipher text")
        }
        let sigEncoded = params["s"]
        let spParam = params["sp"] ?? "signature"

        guard let decodedUrl = urlParam.removingPercentEncoding else {
            throw CipherError.invalidResponse("Could not decode URL")
        }

        // Use player's own buildSignedUrl() which matches YouTube's s2:
        //   g.lq → set("alr","yes") → fJ(24,1210,decodeURI(sig)) → set(sp,sig) → toString()
        if let sig = sigEncoded {
            let result = try await evaluateJS(
                "buildSignedUrl(\(escapeJs(decodedUrl)), \(escapeJs(spParam)), \(escapeJs(sig)))"
            )
            if let builtUrl = result, !builtUrl.isEmpty {
                return builtUrl
            }
            print("[CipherWebView] buildSignedUrl returned nil, falling back to string concat")
        }

        // Fallback: old approach
        var url = decodedUrl
        if let sig = sigEncoded {
            let deobfuscated = try await evaluateJS(
                "deobfuscateSig(null,null,\(escapeJs(sig)))"
            )
            if let deobfuscated = deobfuscated {
                let sep = url.contains("?") ? "&" : "?"
                let encodedSig = deobfuscated.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deobfuscated
                url += "\(sep)\(spParam)=\(encodedSig)"
            }
        }

        // n-normalization via gN$ (syncs /n/ path with ?n= param)
        if let normalized = try? await evaluateJS(
            "normalizeUrl(\(escapeJs(url)))"
        ), !normalized.isEmpty {
            url = normalized
        }

        return url
    }

    // MARK: - Private

    private func evaluateJS(_ script: String) async throws -> String? {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String?, Error>) in
            Task { [weak self] in
                guard let self = self else {
                    cont.resume(throwing: CipherError.jsExecutionFailed("deallocated"))
                    return
                }
                let wv = await self.webView
                await MainActor.run {
                    wv?.evaluateJavaScript(script) { result, error in
                        if let error = error {
                            cont.resume(throwing: CipherError.jsExecutionFailed(error.localizedDescription))
                            return
                        }
                        if let result = result as? String {
                            cont.resume(returning: result)
                        } else if let result = result {
                            cont.resume(returning: String(describing: result))
                        } else {
                            cont.resume(returning: nil)
                        }
                    }
                }
            }
        }
    }

    private func escapeJs(_ str: String) -> String {
        let escaped = str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    private func parseQueryString(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                result[String(parts[0])] = String(parts[1])
            }
        }
        return result
    }

    fileprivate func handleReady() {
        if let cont = readyContinuation {
            cont.resume(returning: ())
            readyContinuation = nil
        }
    }

    fileprivate func handleError(_ error: String) {
        if let cont = readyContinuation {
            cont.resume(throwing: CipherError.jsExecutionFailed(error))
            readyContinuation = nil
        }
    }
}

private final class CipherMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var cipher: CipherWebView?

    @MainActor init(cipher: CipherWebView) {
        self.cipher = cipher
    }

    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        guard message.name == "cipher",
              let body = message.body as? String,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        Task { [weak self] in
            switch type {
            case "ready":
                await self?.cipher?.handleReady()
            case "sigError", "nError", "error":
                if let error = json["error"] as? String {
                    print("[CipherWebView] JS \(type): \(error)")
                }
            default:
                break
            }
        }
    }
}
