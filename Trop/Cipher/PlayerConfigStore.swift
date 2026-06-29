//
//  PlayerConfigStore.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import Foundation

struct PlayerConfig: Codable, Sendable {
    /// Pre-extracted function info for the decipher function
    var sigFunction: ExtractedFunction
    /// Pre-extracted function info for the n-transform function
    var nFunction: ExtractedFunction
}

struct ExtractedFunction: Codable, Sendable {
    /// The raw JavaScript function body (without `function...{` and `}`)
    var body: String?
    /// Regex pattern to locate the function in a fresh player.js
    var extractPattern: String?
    /// Name of the variable/object holding the function, e.g. "a.sig"
    var varName: String?
}

/// Bundled JSON config of known player hashes → cipher extraction info.
/// Falls back to heuristic regex extraction for unknown hashes.
actor PlayerConfigStore {
    static let shared = PlayerConfigStore()

    private var remoteConfigURL = URL(string: "https://raw.githubusercontent.com/username/player-configs/main/player_configs.json")!

    private var configs: [String: PlayerConfig] = [:]
    private var loaded = false

    private init() {}

    func config(for hash: String) async -> PlayerConfig? {
        if !loaded { await loadConfigs() }
        return configs[hash]
    }

    func setRemoteConfigURL(_ url: URL) {
        remoteConfigURL = url
    }

    private func loadConfigs() async {
        // 1. Try bundled config
        if let bundled = try? loadBundled() {
            configs = bundled
            loaded = true
            print("[CipherConfig] Loaded \(configs.count) configs from bundle")
            return
        }
        // 2. Try remote
        if let remote = try? await loadRemote() {
            configs = remote
            loaded = true
            print("[CipherConfig] Loaded \(configs.count) configs from remote")
            return
        }
        // 3. Empty — all extraction will use heuristics
        configs = [:]
        loaded = true
        print("[CipherConfig] No configs available, using heuristic extraction only")
    }

    private func loadBundled() throws -> [String: PlayerConfig]? {
        guard let url = Bundle.main.url(forResource: "player_configs", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoded = try JSONDecoder().decode([String: PlayerConfig].self, from: data)
        return decoded
    }

    private func loadRemote() async throws -> [String: PlayerConfig]? {
        let (data, resp) = try await URLSession.shared.data(from: remoteConfigURL)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        let decoded = try JSONDecoder().decode([String: PlayerConfig].self, from: data)
        return decoded
    }
}
