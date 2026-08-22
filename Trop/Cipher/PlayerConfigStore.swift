//
//  PlayerConfigStore.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import Foundation

struct PlayerConfig: Codable, Sendable, Equatable {
    var sig: String?
    var nClass: String?
    var sts: Int?
    var aliases: [String]?

    var sigFunction: ExtractedFunction {
        ExtractedFunction(body: sig, varName: nil)
    }

    var nFunction: ExtractedFunction {
        ExtractedFunction(body: nil, varName: nClass)
    }

    /// Builds an n-transform IIFE from nClass.
    /// Creates a URL builder instance, injects the n-value, and reads it back via .get('n')
    /// — the builder's class transforms the n-value internally.
    var nJsExpression: String? {
        guard let nClass = nClass else { return nil }
        return "(function(n){try{var u=new g.\(nClass)('https://x.googlevideo.com/videoplayback?n='+n,true);var t=u.get('n');return(t&&t!==n)?t:n;}catch(e){return n;}})(INPUT)"
    }
}

struct ExtractedFunction: Codable, Sendable {
    var body: String?
    var extractPattern: String?
    var varName: String?
}

/// Bundled + remote JSON config of known player hashes → cipher extraction info,
/// ported from zemer-cipher's PlayerConfigStore/PlayerConfigParser:
/// bundled asset as the offline default, overlaid by the same JSON fetched from
/// the zemer-cipher repo so rotated players self-heal without an app update.
///
/// Security boundary: `sig`/`nClass` end up evaluated as JavaScript inside the
/// cipher WebView, so entries are regex-locked to shapes that cannot carry
/// arbitrary JS — `sig` must be a single `name(int,int,INPUT)` call and `nClass`
/// a bare identifier. The n-transform IIFE is built locally from nClass.
actor PlayerConfigStore {
    static let shared = PlayerConfigStore()

    private static let remoteURL = URL(string:
        "https://raw.githubusercontent.com/ZemerTeam/zemer-cipher/master/library/src/main/assets/player_configs.json"
    )!

    private let refreshTTL: TimeInterval = 6 * 60 * 60          // mirrors PlayerJsFetcher cache TTL
    private let forcedRefreshCooldown: TimeInterval = 5 * 60    // unknown-hash misses must not hammer GitHub

    // Validation locks (mirrors upstream PlayerConfigParser)
    private let sigRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9$_]{1,8}\\(\\d+,\\d+,INPUT\\)$")
    private let nClassRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9$_]{1,8}$")
    private let hashRegex = try! NSRegularExpression(pattern: "^[a-f0-9]{8}$")

    /// Advances every time a remote refresh changes the table. The cipher WebView records
    /// the epoch it was built under and rebuilds when this advances, so a corrected config
    /// for the current player takes effect on the next decipher without a restart.
    private(set) var configEpoch = 0

    private var bundledConfigs: [String: PlayerConfig] = [:]
    private var aliasToHash: [String: String] = [:]
    private var mergedConfigs: [String: PlayerConfig] = [:]

    private var loaded = false
    private var lastFetchTime: TimeInterval = 0
    private var etag: String?

    // Cooldown stamps for the failure-triggered paths. Kept separate so one path can never
    // starve the other; both only arm when the server was actually reached.
    private var lastForcedAttempt: TimeInterval = 0
    private var lastRejectionAttempt: TimeInterval = 0
    private var refreshInFlight = false
    /// True when the most recent fetch got ANY HTTP response. The forced-refresh cooldown
    /// only arms in that case — it protects the config host, not recovery after a pure
    /// network failure (e.g. a rotation landing while offline).
    private var lastAttemptReachedServer = false

    private init() {}

    // MARK: - Lookup

    func config(for hash: String) async -> PlayerConfig? {
        if !loaded { await loadConfigs() }
        if let direct = mergedConfigs[hash] { return direct }
        if let hash = aliasToHash[hash] { return mergedConfigs[hash] }
        return nil
    }

    /// Failure-triggered refresh: called when a player-hash lookup misses. Single-flight,
    /// cooldown-gated. Returns true iff `missingHash` is now in the table — whether this
    /// fetch did it or a concurrent refresh already brought it in.
    @discardableResult
    func forceRefresh(missingHash: String) async -> Bool {
        if !loaded { await loadConfigs() }
        if mergedConfigs[missingHash] != nil || aliasToHash[missingHash] != nil { return true }

        let now = Date().timeIntervalSince1970
        guard !withinWindow(now: now, stamp: lastForcedAttempt, window: forcedRefreshCooldown) else {
            Log.cipherConfig.debug("forceRefresh skipped (cooldown)")
            return false
        }
        lastForcedAttempt = now
        await fetchAndApply()
        if !lastAttemptReachedServer { lastForcedAttempt = 0 }
        return mergedConfigs[missingHash] != nil || aliasToHash[missingHash] != nil
    }

    /// Stream-rejection refresh: a deciphered URL was rejected by the CDN (403), which can
    /// mean the cipher produced a wrong-but-non-throwing signature from a stale config.
    /// Unlike forceRefresh this does NOT short-circuit when the hash is present (the entry
    /// may be wrong), and has its own cooldown.
    func notifyStreamRejection() async {
        if !loaded { await loadConfigs() }
        let now = Date().timeIntervalSince1970
        guard !withinWindow(now: now, stamp: lastRejectionAttempt, window: forcedRefreshCooldown) else { return }
        lastRejectionAttempt = now
        await fetchAndApply()
        if !lastAttemptReachedServer { lastRejectionAttempt = 0 }
    }

    /// A backward clock adjustment makes the delta negative — a plain less-than would then
    /// hold the window for the entire skew duration. In-range check instead.
    private func withinWindow(now: TimeInterval, stamp: TimeInterval, window: TimeInterval) -> Bool {
        let delta = now - stamp
        return delta >= 0 && delta < window
    }

    // MARK: - Loading

    private func loadConfigs() async {
        loaded = true
        bundledConfigs = loadBundled() ?? [:]
        rebuildAliasMap(bundledConfigs)
        Log.cipherConfig.debug("Loaded \(bundledConfigs.count) bundled configs")

        // Overlay the last-good cached remote copy. On ANY failure to parse it, delete the
        // body AND meta together: an ETag surviving a corrupt body would make every later
        // conditional fetch 304 without re-downloading, locking us on bundled-only configs.
        if let cachedText = readFile(configsCacheURL),
           let cached = Self.parse(text: cachedText, regexes: regexes) {
            applyRemote(cached, persistBody: false)
            if let meta = readMeta() {
                etag = meta.etag
                lastFetchTime = meta.timestamp
            }
        } else if FileManager.default.fileExists(atPath: configsCacheURL?.path ?? "-") {
            removeFile(configsCacheURL)
            removeFile(metaCacheURL)
        }

        // Non-blocking-style TTL refresh for app start
        if !withinWindow(now: Date().timeIntervalSince1970, stamp: lastFetchTime, window: refreshTTL) {
            await fetchAndApply()
        }
    }

    // MARK: - Fetch & Apply

    private func fetchAndApply() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }

        var request = URLRequest(url: Self.remoteURL)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        guard let (data, response) = try? await URLSession.shared.blockingData(for: request),
              let http = response as? HTTPURLResponse else {
            lastAttemptReachedServer = false
            Log.cipherConfig.notice("Remote config fetch failed (network) — keeping previous configs")
            return
        }
        lastAttemptReachedServer = true

        if http.statusCode == 304 {
            etag = http.value(forHTTPHeaderField: "ETag") ?? etag
            lastFetchTime = Date().timeIntervalSince1970
            writeMeta()
            return
        }
        guard http.statusCode == 200,
              let body = String(data: data, encoding: .utf8), !body.isEmpty else {
            Log.cipherConfig.notice("Remote config fetch HTTP \(http.statusCode) — keeping previous configs")
            return
        }

        guard let remote = Self.parse(text: body, regexes: regexes) else {
            Log.cipherConfig.notice("Remote configs rejected (validation) — keeping previous configs")
            return
        }

        etag = http.value(forHTTPHeaderField: "ETag") ?? ""
        lastFetchTime = Date().timeIntervalSince1970
        applyRemote(remote, persistBody: true, rawBody: body)
        writeMeta()
    }

    private var regexes: (sig: NSRegularExpression, nClass: NSRegularExpression, hash: NSRegularExpression) {
        (sigRegex, nClassRegex, hashRegex)
    }

    /// Applies a validated table to memory first, then best-effort persists. Merged =
    /// bundled + remote with remote winning per key; bundled-only keys survive.
    private func applyRemote(_ remote: [String: PlayerConfig], persistBody: Bool, rawBody: String? = nil) {
        var merged = bundledConfigs
        merged.merge(remote) { _, remoteEntry in remoteEntry }
        rebuildAliasMap(merged)

        let changed = merged != mergedConfigs
        mergedConfigs = merged
        if changed { configEpoch += 1 }
        Log.cipherConfig.debug("Remote configs applied (\(remote.count) hashes, merged=\(merged.count), changed=\(changed))")

        if persistBody, let rawBody {
            writeFile(configsCacheURL, rawBody)
        }
    }

    private func rebuildAliasMap(_ configs: [String: PlayerConfig]) {
        var map: [String: String] = [:]
        for (hash, entry) in configs {
            for alias in entry.aliases ?? [] where alias != hash {
                map[alias] = hash
            }
        }
        aliasToHash = map
    }

    // MARK: - Parsing / validation (port of upstream PlayerConfigParser)

    /// Parses and validates a config document. File-level problems return nil (callers keep
    /// their previous table); invalid individual entries are skipped so one bad entry can't
    /// poison the rest. Duplicate hash/alias keys make the table ambiguous → whole-file reject.
    static func parse(text: String, regexes: (sig: NSRegularExpression, nClass: NSRegularExpression, hash: NSRegularExpression)) -> [String: PlayerConfig]? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let schemaVersion = intPrimitive(root["schemaVersion"]), schemaVersion > 0, schemaVersion <= 1 else {
            return nil
        }
        guard let players = root["players"] as? [String: Any] else { return nil }

        var configs: [String: PlayerConfig] = [:]
        for (hash, entryAny) in players {
            guard let entry = entryAny as? [String: Any],
                  matches(regexes.hash, hash),
                  let sig = stringPrimitive(entry["sig"]), matches(regexes.sig, sig),
                  let nClass = stringPrimitive(entry["nClass"]), matches(regexes.nClass, nClass),
                  let sts = intPrimitive(entry["sts"]), sts > 0 else {
                continue
            }
            var aliases: [String] = []
            if let aliasArray = entry["aliases"] as? [Any] {
                var valid = true
                for aliasAny in aliasArray {
                    guard let alias = stringPrimitive(aliasAny), matches(regexes.hash, alias) else {
                        valid = false
                        break
                    }
                    aliases.append(alias)
                }
                guard valid else { continue }
            }

            let keys = [hash] + aliases
            if Set(keys).count != keys.count || keys.contains(where: { configs[$0] != nil }) {
                return nil
            }
            configs[hash] = PlayerConfig(sig: sig, nClass: nClass, sts: sts, aliases: aliases)
        }
        return configs
    }

    private static func matches(_ regex: NSRegularExpression, _ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range)?.range.length == range.length
    }

    private static func stringPrimitive(_ any: Any?) -> String? {
        any as? String
    }

    /// Non-string primitives only: a string-typed "1" must fail like upstream.
    private static func intPrimitive(_ any: Any?) -> Int? {
        guard !(any is String), let number = any as? NSNumber else { return nil }
        return number.intValue
    }

    // MARK: - Disk helpers

    private var storeDir: URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let dir = documents?.appendingPathComponent("Trop/Player", isDirectory: true)
        // Deliberately not prefixed "player_" — PlayerJsFetcher purges player_* files here.
        return dir
    }

    private var configsCacheURL: URL? { storeDir?.appendingPathComponent("configs_remote.json") }
    private var metaCacheURL: URL? { storeDir?.appendingPathComponent("configs_remote.meta") }

    private func loadBundled() -> [String: PlayerConfig]? {
        guard let url = Bundle.main.url(forResource: "player_configs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return Self.parse(text: text, regexes: regexes)
    }

    private struct Meta {
        let etag: String
        let timestamp: TimeInterval
    }

    private func readMeta() -> Meta? {
        guard let text = readFile(metaCacheURL) else { return nil }
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard lines.count == 2, let timestamp = TimeInterval(lines[1]) else { return nil }
        return Meta(etag: String(lines[0]), timestamp: timestamp)
    }

    private func writeMeta() {
        guard let url = metaCacheURL else { return }
        writeFile(url, "\(etag ?? "")\n\(lastFetchTime)")
    }

    private func readFile(_ url: URL?) -> String? {
        guard let url, let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeFile(_ url: URL?, _ content: String) {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func removeFile(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

private extension URLSession {
    /// Small helper so the actor can do a blocking-style request without wrapping
    /// continuation boilerplate at each call site.
    func blockingData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            let task = self.dataTask(with: request) { data, response, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: (data ?? Data(), response ?? URLResponse()))
                }
            }
            task.resume()
        }
    }
}
