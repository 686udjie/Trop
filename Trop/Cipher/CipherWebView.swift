//
//  CipherWebView.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import WebKit
import Foundation

@MainActor
final class CipherWebView: NSObject {
    static let shared = CipherWebView()

    private var isReady = false
    private var playerHash: String?
    private var builtConfigEpoch = 0
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var loadTask: Task<Void, Error>?

    private var webView: WKWebView?

    private var playerDir: URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let dir = documents?.appendingPathComponent("Player", isDirectory: true)
        return dir
    }

    private override init() {
        super.init()
    }

    func load() async throws {
        let hash = try await PlayerJsFetcher.shared.getPlayerHash()

        let epoch = await PlayerConfigStore.shared.configEpoch
        if isReady, self.playerHash == hash, builtConfigEpoch == epoch {
            return
        }

        if let existing = loadTask {
            try await existing.value
            return
        }

        let task = Task { [self] in
            try await self.performLoad(hash: hash)
        }
        loadTask = task
        defer { loadTask = nil }
        try await task.value
    }

    private func performLoad(hash: String) async throws {
        self.playerHash = hash
        self.builtConfigEpoch = await PlayerConfigStore.shared.configEpoch

        let playerJs = try await PlayerJsFetcher.shared.getPlayerJs()

        let sigConfig: String?
        let nClass: String?
        let nJsExpression: String?
        let isExpression: Bool
        var rawNFuncBody: String?
        var config = await PlayerConfigStore.shared.config(for: hash)
        if config == nil {
            _ = await PlayerConfigStore.shared.forceRefresh(missingHash: hash)
            config = await PlayerConfigStore.shared.config(for: hash)
        }
        if let config {
            sigConfig = config.sigFunction.body
            nClass = config.nFunction.varName
            nJsExpression = config.nJsExpression
            isExpression = true
            Log.cipherWebView.debug("Config found: sig=\(sigConfig ?? "?"), nClass=\(nClass ?? "?"), hasNtransform=\(nJsExpression != nil)")
        } else {
            Log.cipherWebView.debug("No config for hash \(hash), trying heuristic extraction")
            let extracted = try? await FunctionNameExtractor.shared.extract(from: playerJs, playerHash: hash)
            if let js = extracted?.sigJs, !js.isEmpty {
                let raw = js.hasPrefix("(") && js.hasSuffix(")") ? String(js.dropFirst().dropLast()) : js
                sigConfig = raw
                isExpression = false
                Log.cipherWebView.debug("Heuristic extraction succeeded")
            } else {
                sigConfig = nil
                isExpression = false
                Log.cipherWebView.notice("Heuristic extraction failed, using fallback")
            }
            if let nClassHeuristic = extracted?.nClass {
                nClass = nClassHeuristic
                nJsExpression = PlayerConfig(nClass: nClassHeuristic).nJsExpression
                rawNFuncBody = nil
                Log.cipherWebView.debug("Extracted nClass=\(nClassHeuristic) heuristically")
            } else if let nJs = extracted?.nJs {
                nClass = nil
                nJsExpression = nil
                let raw = nJs.hasPrefix("(") && nJs.hasSuffix(")") ? String(nJs.dropFirst().dropLast()) : nJs
                rawNFuncBody = raw
                Log.cipherWebView.debug("Extracted n-transform function heuristically")
            } else {
                nClass = nil
                nJsExpression = nil
                rawNFuncBody = nil
                Log.cipherWebView.debug("No n-transform found via heuristics")
            }
        }

        let patchedJs = CipherHTMLBuilder.patchPlayerJs(
            playerJs: playerJs,
            sigConfig: sigConfig,
            sigIsExpression: isExpression,
            nClass: nClass,
            nJsExpression: nJsExpression,
            rawNFuncBody: rawNFuncBody,
            playerHash: hash
        )

        guard let dir = playerDir else { throw CipherError.cacheUnavailable }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Log.cipherWebView.debug("Player directory: \(dir.path)")
        let playerFile = dir.appendingPathComponent("base_\(hash).js")
        try patchedJs.write(to: playerFile, atomically: true, encoding: .utf8)

        let html = CipherHTMLBuilder.buildFileBasedHTML(playerHash: hash)
        let htmlFile = dir.appendingPathComponent("cipher_\(hash).html")
        try html.write(to: htmlFile, atomically: true, encoding: .utf8)

        let handler = CipherMessageHandler(cipher: self)
        let webConfig = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(handler, name: "cipher")
        webConfig.userContentController = userContent
        webConfig.suppressesIncrementalRendering = true

        let w = WKWebView(frame: .zero, configuration: webConfig)
        w.isHidden = true
        self.webView = w

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.readyContinuation = cont
            self.scheduleReadyTimeout()
            w.loadFileURL(htmlFile, allowingReadAccessTo: dir)
        }

        self.isReady = true
        Log.cipherWebView.debug("Ready (file-based, hash=\(hash))")
    }

    private func scheduleReadyTimeout() {
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            handleTimeout()
        }
    }

    func handleTimeout() {
        if let cont = readyContinuation {
            readyContinuation = nil
            cont.resume(throwing: CipherError.jsExecutionFailed("WebView ready timeout"))
        }
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

        var url = decodedUrl
        if let sig = sigEncoded {
            let result = try await evaluateJS(
                "buildSignedUrl(\(escapeJs(decodedUrl)), \(escapeJs(spParam)), \(escapeJs(sig)))"
            )
            if let builtUrl = result, builtUrl.hasPrefix("http") {
                url = builtUrl
            } else {
                let deobfuscated = try await evaluateJS(
                    "deobfuscateSig(null,null,\(escapeJs(sig)))"
                )
                if let deobfuscated = deobfuscated {
                    let sep = url.contains("?") ? "&" : "?"
                    let encodedSig = deobfuscated.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deobfuscated
                    url += "\(sep)\(spParam)=\(encodedSig)"
                } else {
                    throw CipherError.deobfuscationFailed("sig deobfuscation returned nil (no cipher function exported)")
                }
            }
        }

        if let nValue = extractNParam(from: url) {
            if let transformed = try? await evaluateJS(
                "transformN(\(escapeJs(nValue)))"
            ), !transformed.isEmpty, transformed != nValue {
                let pattern = "(?<=[?&])n=\(NSRegularExpression.escapedPattern(for: nValue))(?=&|$)"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(url.startIndex..., in: url)
                    url = regex.stringByReplacingMatches(in: url, range: range, withTemplate: "n=\(transformed)")
                }
            } else {
                let pattern = "&?n=\(NSRegularExpression.escapedPattern(for: nValue))(?=&|$)"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(url.startIndex..., in: url)
                    url = regex.stringByReplacingMatches(in: url, range: range, withTemplate: "")
                        .replacingOccurrences(of: "?&", with: "?")
                        .replacingOccurrences(of: "\\?$", with: "", options: .regularExpression)
                }
            }
        }

        return url
    }

    // MARK: - Private

    private func evaluateJS(_ script: String) async throws -> String? {
        guard let wv = webView else {
            throw CipherError.jsExecutionFailed("webView is nil")
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String?, Error>) in
            var timeoutTask: Task<Void, Never>?
            let lock = NSLock()

            func resumeOnce(_ block: (CheckedContinuation<String?, Error>) -> Void) {
                lock.lock()
                defer { lock.unlock() }
                guard timeoutTask != nil else { return }
                timeoutTask = nil
                block(cont)
            }

            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                resumeOnce { cont in
                    cont.resume(throwing: CipherError.jsExecutionFailed("JS evaluation timed out"))
                }
            }

            wv.evaluateJavaScript(script) { result, error in
                resumeOnce { cont in
                    if let error {
                        cont.resume(throwing: CipherError.jsExecutionFailed(error.localizedDescription))
                    } else if let result {
                        cont.resume(returning: result as? String)
                    } else {
                        cont.resume(returning: nil)
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

    func handleReady() {
        if let cont = readyContinuation {
            readyContinuation = nil
            cont.resume(returning: ())
        }
    }

    func handleError(_ error: String) {
        if let cont = readyContinuation {
            readyContinuation = nil
            cont.resume(throwing: CipherError.jsExecutionFailed(error))
        }
    }
}

// MARK: - Message Handler

private final class CipherMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var cipher: CipherWebView?

    init(cipher: CipherWebView) {
        self.cipher = cipher
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "cipher",
              let body = message.body as? String,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        Task { @MainActor in
            switch type {
            case "ready":
                self.cipher?.handleReady()
            case "discovery":
                let sig = json["sigFuncName"] as? String ?? "?"
                let n = json["nFuncName"] as? String ?? "?"
                let info = json["info"] as? String ?? ""
                Log.cipherWebView.info("Cipher discovery: sig=\(sig) n=\(n) (\(info))")
            case "sigError", "nError", "error":
                let msg = json["error"] as? String ?? "unknown JS error"
                Log.cipherWebView.error("JS \(type): \(msg)")
                self.cipher?.handleError(msg)
            default:
                break
            }
        }
    }
}
