//
//  PlayerJsFetcher.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import Foundation

// Downloads and caches YouTube's player.js which contains cipher functions
// for stream URL signature deobfuscation and n-parameter transform.
actor PlayerJsFetcher {
    static let shared = PlayerJsFetcher()

    private let cacheLifetime: TimeInterval = 6 * 60 * 60  // 6 hours

    private var cacheDir: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("cipher_cache", isDirectory: true)
    }

    private init() {}

    // Returns the current player.js content, fetching if needed
    func getPlayerJs() async throws -> String {
        try ensureCacheDir()
        if let cached = try loadCachedPlayerJs() {
            return cached
        }
        let (hash, js) = try await fetchPlayerJs()
        try saveCache(hash: hash, js: js)
        return js
    }

    // Returns the signature timestamp from the current player.js
    func getSignatureTimestamp() async throws -> Int {
        let js = try await getPlayerJs()
        return try Self.extractSignatureTimestamp(from: js)
    }

    // MARK: - Fetch Pipeline

    private func fetchPlayerJs() async throws -> (hash: String, js: String) {
        let hash = try await fetchPlayerHash()
        let js = try await downloadPlayerJs(hash: hash)
        return (hash, js)
    }

    private func fetchPlayerHash() async throws -> String {
        let url = URL(string: "https://www.youtube.com/iframe_api")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CipherError.invalidResponse("iframe_api not UTF-8")
        }
        let nsText = text as NSString
        guard let pattern = try? NSRegularExpression(pattern: #"\\?/s\\?/player\\?/([\w-]+)\\?/"#, options: []) else {
            throw CipherError.hashNotFound
        }
        guard let match = pattern.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            throw CipherError.hashNotFound
        }
        return nsText.substring(with: match.range(at: 1))
    }

    // Downloads player.js for a given hash
    private func downloadPlayerJs(hash: String) async throws -> String {
        let url = URL(string: "https://www.youtube.com/s/player/\(hash)/player_ias.vflset/en_GB/base.js")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let js = String(data: data, encoding: .utf8) else {
            throw CipherError.invalidResponse("player.js not UTF-8")
        }
        return js
    }

    // MARK: - Cache

    private func ensureCacheDir() throws {
        guard let dir = cacheDir else { throw CipherError.cacheUnavailable }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func cachePath(hash: String) -> URL? {
        cacheDir?.appendingPathComponent("player_\(hash).js")
    }

    private var hashInfoPath: URL? {
        cacheDir?.appendingPathComponent("current_hash.txt")
    }

    private func loadCachedPlayerJs() throws -> String? {
        guard let infoPath = hashInfoPath,
              let infoData = try? Data(contentsOf: infoPath),
              let info = String(data: infoData, encoding: .utf8) else {
            return nil
        }
        let lines = info.split(separator: "\n", maxSplits: 1)
        guard lines.count == 2,
              let timestamp = TimeInterval(lines[1]) else {
            return nil
        }
        // Check TTL
        guard Date().timeIntervalSince1970 - timestamp < cacheLifetime else {
            return nil
        }
        let hash = String(lines[0])
        guard let jsPath = cachePath(hash: hash),
              let js = try? String(contentsOf: jsPath, encoding: .utf8) else {
            return nil
        }
        print("[Cipher] Using cached player.js (hash=\(hash))")
        return js
    }

    private func saveCache(hash: String, js: String) throws {
        // Save JS file
        if let jsPath = cachePath(hash: hash) {
            try js.write(to: jsPath, atomically: true, encoding: .utf8)
        }
        // Save hash info
        let info = "\(hash)\n\(Date().timeIntervalSince1970)"
        if let infoPath = hashInfoPath {
            try info.write(to: infoPath, atomically: true, encoding: .utf8)
        }
        print("[Cipher] Cached player.js (hash=\(hash))")
    }

    // MARK: - Signature Timestamp Extraction

    static func extractSignatureTimestamp(from js: String) throws -> Int {
        let nsJs = js as NSString
        guard let pattern = try? NSRegularExpression(pattern: #"signatureTimestamp["':\s]+(\d+)"#, options: []) else {
            throw CipherError.signatureTimestampNotFound
        }
        guard let match = pattern.firstMatch(in: js, range: NSRange(location: 0, length: nsJs.length)) else {
            throw CipherError.signatureTimestampNotFound
        }
        let value = nsJs.substring(with: match.range(at: 1))
        return Int(value) ?? 0
    }
}

enum CipherError: Error, LocalizedError {
    case hashNotFound
    case invalidResponse(String)
    case cacheUnavailable
    case signatureTimestampNotFound
    case functionNotFound(String)
    case jsExecutionFailed(String)
    case configNotAvailable

    var errorDescription: String? {
        switch self {
        case .hashNotFound: return "Player hash not found in iframe_api"
        case .invalidResponse(let msg): return "Invalid response: \(msg)"
        case .cacheUnavailable: return "Cache directory unavailable"
        case .signatureTimestampNotFound: return "Signature timestamp not found in player.js"
        case .functionNotFound(let name): return "Cipher function not found: \(name)"
        case .jsExecutionFailed(let msg): return "JS execution failed: \(msg)"
        case .configNotAvailable: return "No config entry for this player hash"
        }
    }
}
