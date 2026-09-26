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

    private struct ProviderHit: Sendable {
        let order: Int
        let lines: [LyricLine]
        let providerName: String
    }

    func fetchLyricsReturningProvider(query: LyricsQuery) async throws -> ([LyricLine], providerName: String?) {
        let order = await LyricsSettings.shared.providerOrder
        let disabled = SettingsStore.shared.disabledLyricsProviders
        let candidates: [(index: Int, provider: LyricsProvider)] = order.enumerated().compactMap { index, id in
            guard !disabled.contains(id), let provider = LyricsProviderRegistry.provider(for: id) else { return nil }
            return (index, provider)
        }
        guard !candidates.isEmpty else { throw LyricsError.notFound }

        let results = await withTaskGroup(of: ProviderHit?.self) { group in
            for (index, provider) in candidates {
                group.addTask {
                    do {
                        let lines = try await Self.withTimeout(seconds: 10) {
                            try await provider.fetch(query: query)
                        }
                        guard !lines.isEmpty else { return nil }
                        return ProviderHit(order: index, lines: lines, providerName: provider.name)
                    } catch {
                        return nil
                    }
                }
            }
            var collected: [ProviderHit] = []
            for await item in group {
                if let item { collected.append(item) }
            }
            return collected
        }
        guard let best = results.min(by: { $0.order < $1.order }) else {
            throw LyricsError.notFound
        }
        return (best.lines, best.providerName)
    }

    private static func withTimeout<T: Sendable>(seconds: Double, work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw LyricsError.notFound
            }
            guard let first = try await group.next() else {
                group.cancelAll()
                throw LyricsError.notFound
            }
            group.cancelAll()
            return first
        }
    }
}
