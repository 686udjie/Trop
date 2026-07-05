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
        let nJsExpression: String?
        let isExpression: Bool
        if let config = await PlayerConfigStore.shared.config(for: hash) {
            sigConfig = config.sigFunction.body
            nClass = config.nFunction.varName
            nJsExpression = config.nJsExpression
            isExpression = true
            print("[CipherWebView] Config found: sig=\(sigConfig ?? "?"), nClass=\(nClass ?? "?"), hasNtransform=\(nJsExpression != nil)")
        } else {
            print("[CipherWebView] No config for hash \(hash), trying heuristic extraction")
            let extracted = try? await FunctionNameExtractor.shared.extract(from: playerJs, playerHash: hash)
            if let js = extracted?.sigJs {
                // Strip the outer parens to get the raw function declaration
                let raw = js.hasPrefix("(") && js.hasSuffix(")") ? String(js.dropFirst().dropLast()) : js
                sigConfig = raw
                isExpression = false
                print("[CipherWebView] Heuristic extraction succeeded")
            } else {
                sigConfig = nil
                isExpression = false
                print("[CipherWebView] Heuristic extraction failed, using fallback")
            }
            nClass = nil
            nJsExpression = nil
        }

        // Patch player.js to expose cipher functions on window
        let patchedJs = CipherHTMLBuilder.patchPlayerJs(
            playerJs: playerJs,
            sigConfig: sigConfig,
            sigIsExpression: isExpression,
            nClass: nClass,
            nJsExpression: nJsExpression,
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

        // n-transform: transform the n-parameter value via the URL builder class
        // to avoid CDN throttling/403. Required for WEB_REMIX, WEB, etc.
        if let nValue = extractNParam(from: url) {
            print("[CipherWebView] n-param found, transforming: \(nValue)")
            if let transformed = try? await evaluateJS(
                "transformN(\(escapeJs(nValue)))"
            ), !transformed.isEmpty, transformed != nValue {
                // Replace the n= param with the transformed value
                let pattern = "(?<=[?&])n=\(NSRegularExpression.escapedPattern(for: nValue))(?=&|$)"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(url.startIndex..., in: url)
                    url = regex.stringByReplacingMatches(in: url, range: range, withTemplate: "n=\(transformed)")
                }
                print("[CipherWebView] n-transform: \(nValue) -> \(transformed)")
            } else {
                print("[CipherWebView] n-transform returned same value or failed, keeping original")
            }
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
                        } else if result is NSNull {
                            cont.resume(returning: nil)
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

    /// Extracts the value of the `n` parameter from a URL, or nil if not present.
    private func extractNParam(from url: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "[?&]n=([^&]+)", options: []) else { return nil }
        let range = NSRange(url.startIndex..., in: url)
        if let match = regex.firstMatch(in: url, range: range) {
            let valueRange = match.range(at: 1)
            guard valueRange.location != NSNotFound else { return nil }
            return (url as NSString).substring(with: valueRange)
        }
        return nil
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
