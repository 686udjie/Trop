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
        Log.explore.debug("Explore fetch start browseId=\(HomePageParser.exploreBrowseId)")
        do {
            let json = try await InnerTube.shared.browse(browseId: HomePageParser.exploreBrowseId)
            Log.explore.debug("Explore fetch ok topKeys=\((json.keys.sorted()))")
            sections = HomePageParser.parseExploreSections(from: json)
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

    // MARK: - Moods

    /// Full category page (songs, playlists, videos, albums shelves).
    static func loadMoodDetail(_ mood: MoodItem) async -> [ExploreSection] {
        Log.explore.debug("Explore mood '\(mood.title)' fetch params=\(mood.params ?? "none")")
        do {
            let json = try await InnerTube.shared.browse(
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

    // MARK: - Playback

    /// Plays a song then continues with its radio queue (shared by the
    /// Explore list and mood pages).
    static func playSong(_ song: SongItem) {
        NowPlaying.shared.setQueue([song], startIndex: 0)
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
            } catch {
                Log.explore.error("Playback failed: \(error)")
                return
            }
            guard let radio = try? await PersonalizationService.shared.fetchRadio(videoId: song.videoId),
                  radio.songs.count > 1,
                  NowPlaying.shared.videoId == song.videoId else { return }
            NowPlaying.shared.queueSongs = radio.songs
            NowPlaying.shared.queueIndex = radio.currentIndex
        }
    }
}
