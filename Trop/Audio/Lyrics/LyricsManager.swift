//
//  LyricsManager.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import Foundation

@Observable
final class LyricsSettings {
    static let shared = LyricsSettings()

    private let orderKey = "lyricsProviderOrder"

    /// Ordered provider ids. Defaults to a sensible fallback chain.
    var providerOrder: [String] {
        get {
            let saved: [String]
            if let data = UserDefaults.standard.data(forKey: orderKey),
               let decoded = try? JSONDecoder().decode([String].self, from: data),
               !decoded.isEmpty {
                saved = decoded
            } else {
                saved = LyricsProviderRegistry.defaultOrder
            }
            let merged = saved + LyricsProviderRegistry.defaultOrder.filter { !saved.contains($0) }
            return merged
        }
        set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data()
            UserDefaults.standard.set(data, forKey: orderKey)
        }
    }

    private init() {}
}

/// Registry of all available providers.
enum LyricsProviderRegistry {
    static let all: [LyricsProvider] = [
        LRCLIBProvider(),
        MusixmatchProvider(),
        NeteaseProvider(),
        KugouProvider(),
        GeniusProvider()
    ]

    static let defaultOrder: [String] = [
        "lrclib",
        "musixmatch",
        "netease",
        "kugou",
        "genius"
    ]

    static func provider(for id: String) -> LyricsProvider? {
        all.first { $0.id == id }
    }
}

actor LyricsManager {
    static let shared = LyricsManager()

    private init() {}

    func fetchLyrics(query: LyricsQuery) async throws -> [LyricLine] {
        let order = LyricsSettings.shared.providerOrder
        var lastError: Error?

        for id in order {
            guard let provider = LyricsProviderRegistry.provider(for: id) else { continue }
            print("[Lyrics] trying provider \(id)")
            do {
                let lines = try await provider.fetch(query: query)
                if !lines.isEmpty {
                    print("[Lyrics] provider \(id) returned \(lines.count) lines")
                    return lines
                }
                print("[Lyrics] provider \(id) returned no lines")
            } catch {
                lastError = error
                print("[Lyrics] provider \(id) failed: \(error.localizedDescription)")
                continue
            }
        }

        throw lastError ?? LyricsError.notFound
    }
}
