//
// ExploreViewModel.swift
// Trop
//
// Created by 686udjie on 11/09/2026.
//

import Foundation
import SwiftUI

/// Drives the Explore tab (`FEmusic_explore`): new releases, charts,
/// moods & genres.
@MainActor
@Observable
final class ExploreViewModel {

    enum Phase {
        case idle
        case loading
        case loaded
        case empty
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var sections: [ExploreSection] = []
    private(set) var error: Error?

    private var hasLoaded = false

    // MARK: - Loading

    func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await fetch() }
    }

    func refresh() async {
        await fetch()
    }

    private func fetch() async {
        phase = .loading
        error = nil
        let region = SettingsStore.shared.contentCountry
        Log.explore.debug("Explore fetch start browseId=\(HomePageParser.exploreBrowseId)")
        do {
            let json = try await InnerTubeClient.tropShared.browse(
                browseId: HomePageParser.exploreBrowseId,
                formData: ["selectedValues": [region]]
            )
            Log.explore.debug("Explore fetch ok topKeys=\((json.keys.sorted()))")
            sections = HomePageParser.parseExploreSections(from: json)
            await applyRegionalTrending(region: region)
            let moodCount = sections.reduce(0) { $0 + $1.moods.count }
            Log.explore.debug(
                "Explore loaded: " +
                sections.map { "\($0.title)(\($0.kind)):\($0.items.count)" }.joined(separator: ", ") +
                " moods=\(moodCount)"
            )
            phase = sections.isEmpty ? .empty : .loaded
        } catch {
            Log.explore.error("Explore fetch failed: \(error)")
            self.error = error
            phase = .failed
        }
    }

    /// Swaps the Trending shelf for the region's chart tracks. The explore
    /// carousel follows the IP/account region, which the region setting
    /// cannot move — but per-country charts can, via the country selector.
    /// Falls back to explore's own items on any failure.
    private func applyRegionalTrending(region: String) async {
        guard let index = sections.firstIndex(where: { $0.title.lowercased() == "trending" }) else { return }
        guard let playlistId = try? await RegionalCharts.trendingPlaylistId(country: region, using: InnerTubeClient.tropShared),
              let (_, rows) = try? await SyncBridge.playlistDetail.fetchPlaylistRows(playlistId: playlistId) else { return }
        let songs = rows.compactMap { item -> SongItem? in
            guard let renderer = item["musicResponsiveListItemRenderer"] as? [String: Any] else { return nil }
            return SongItem.from(renderer)
        }
        guard !songs.isEmpty else { return }
        sections[index].items = songs.map(YTItem.song)
        sections[index].kind = .rows
    }

    // MARK: - Moods

    /// Full category page (songs, playlists, videos, albums shelves).
    static func loadMoodDetail(_ mood: MoodItem) async -> [ExploreSection] {
        Log.explore.debug("Explore mood '\(mood.title)' fetch params=\(mood.params ?? "none")")
        do {
            let json = try await InnerTubeClient.tropShared.browse(
                browseId: HomePageParser.moodsCategoryBrowseId,
                params: mood.params
            )
            let sections = HomePageParser.parseExploreSections(from: json)
            Log.explore.debug(
                "Explore mood '\(mood.title)': " +
                sections.map { "\($0.title)(\($0.kind)):\($0.items.count)" }.joined(separator: ", ")
            )
            return sections
        } catch {
            Log.explore.error("Explore mood '\(mood.title)' failed: \(error)")
            return []
        }
    }

}
