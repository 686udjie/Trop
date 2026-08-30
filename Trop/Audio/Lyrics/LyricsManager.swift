//
//  LyricsManager.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import Foundation

@Observable
@MainActor
final class LyricsSettings {
    static let shared = LyricsSettings()

    private let orderKey = "lyricsProviderOrder"

    /// Ordered provider ids. Defaults to a sensible fallback chain.
    var providerOrder: [String] = LyricsProviderRegistry.defaultOrder

    private init() {
        if let data = UserDefaults.standard.data(forKey: orderKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data),
           !decoded.isEmpty {
            providerOrder = decoded + LyricsProviderRegistry.defaultOrder.filter { !decoded.contains($0) }
        }
    }

    func saveProviderOrder(_ order: [String]) {
        providerOrder = order
        let data = (try? JSONEncoder().encode(order)) ?? Data()
        UserDefaults.standard.set(data, forKey: orderKey)
    }
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

    struct LyricSearchResult: Identifiable {
        let id = UUID()
        let lines: [LyricLine]
        let providerName: String
        let sortOrder: Int

        var previewText: String {
            lines.prefix(2).map(\.text).joined(separator: "\n")
        }

        var isSynced: Bool {
            lines.contains { $0.startTime != nil }
        }
    }

    func fetchLyrics(query: LyricsQuery) async throws -> [LyricLine] {
        let (lines, _) = try await fetchLyricsReturningProvider(query: query)
        return lines
    }

    /// Queries every enabled provider concurrently and returns all matches.
    func searchAll(query: LyricsQuery) async -> [LyricSearchResult] {
        let order = await LyricsSettings.shared.providerOrder
        let disabled = SettingsStore.shared.disabledLyricsProviders
        let providers = order
            .compactMap { LyricsProviderRegistry.provider(for: $0) }
            .filter { !disabled.contains($0.id) }
            .enumerated().map { ($1, $0) }

        return await withTaskGroup(of: (Int, LyricSearchResult)?.self) { group in
            for (provider, index) in providers {
                group.addTask {
                    guard let lines = try? await provider.fetch(query: query), !lines.isEmpty else { return nil }
                    return (index, LyricSearchResult(lines: lines, providerName: provider.name, sortOrder: index))
                }
            }
            var results: [(Int, LyricSearchResult)] = []
            for await item in group {
                if let item { results.append(item) }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func fetchLyricsReturningProvider(query: LyricsQuery) async throws -> ([LyricLine], providerName: String?) {
        let order = await LyricsSettings.shared.providerOrder
        let disabled = SettingsStore.shared.disabledLyricsProviders
        var lastError: Error?

        for id in order {
            guard !disabled.contains(id) else { continue }
            guard let provider = LyricsProviderRegistry.provider(for: id) else { continue }
            do {
                let lines = try await provider.fetch(query: query)
                if !lines.isEmpty {
                    return (lines, provider.name)
                }
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? LyricsError.notFound
    }
}
