//
//  PlayerConfigStore.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import Foundation

struct PlayerConfig: Codable, Sendable {
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

/// Bundled + remote JSON config of known player hashes → cipher extraction info.
/// Falls back to regex heuristic extraction for unknown hashes.
actor PlayerConfigStore {
    static let shared = PlayerConfigStore()

    private var configs: [String: PlayerConfig] = [:]
    private var loaded = false

    private init() {}

    func config(for hash: String) async -> PlayerConfig? {
        if !loaded { await loadConfigs() }
        // Direct match
        if let entry = configs[hash] {
            return entry
        }
        // Alias match
        for (_, entry) in configs {
            if let aliases = entry.aliases, aliases.contains(hash) {
                return entry
            }
        }
        return nil
    }

    private func loadConfigs() async {
        // 1. Try bundled config
        if let bundled = try? loadBundled() {
            configs = bundled
            loaded = true
            Log.cipherConfig.debug("Loaded \(configs.count) configs from bundle")
            return
        }
        // 2. Empty — all extraction will use heuristics
        configs = [:]
        loaded = true
        Log.cipherConfig.debug("No bundled config, using heuristic extraction only")
    }

    private func loadBundled() throws -> [String: PlayerConfig]? {
        guard let url = Bundle.main.url(forResource: "player_configs", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoded = try JSONDecoder().decode(PlayerConfigsFile.self, from: data)
        return decoded.players
    }
}

private struct PlayerConfigsFile: Codable {
    let schemaVersion: Int?
    let players: [String: PlayerConfig]
}
