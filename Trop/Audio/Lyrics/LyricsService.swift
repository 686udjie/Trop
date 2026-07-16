//
//  LyricsService.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import Foundation

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let startTime: TimeInterval?

    static let placeholder = LyricLine(text: "♪", startTime: nil)
}

@MainActor
@Observable
final class LyricsState {
    static let shared = LyricsState()

    var isAvailable: Bool = false

    private init() {}
}

actor LyricsService {
    static let shared = LyricsService()

    private var cache: [String: [LyricLine]] = [:]

    private init() {}

    func fetchLyrics(videoId: String) async throws -> [LyricLine] {
        if let cached = cache[videoId] {
            print("[Lyrics] cache hit for \(videoId) (\(cached.count) lines)")
            await updateAvailability(!cached.isEmpty)
            return cached
        }
        guard let query = resolveQuery(videoId: videoId) else {
            print("[Lyrics] no query metadata for \(videoId), skipping")
            await updateAvailability(false)
            throw LyricsError.notFound
        }
        print("[Lyrics] fetching for \"\(query.title)\" — \(query.artist) (\(query.durationSeconds)s)")
        let lines = try await LyricsManager.shared.fetchLyrics(query: query)
        cache[videoId] = lines
        print("[Lyrics] got \(lines.count) lines for \(videoId)")
        await updateAvailability(!lines.isEmpty)
        return lines
    }

    func preload(videoId: String, upcoming: [String] = []) async {
        print("[Lyrics] preload \(videoId) + upcoming \(upcoming)")
        _ = try? await fetchLyrics(videoId: videoId)
        for id in upcoming where cache[id] == nil {
            _ = try? await fetchLyrics(videoId: id)
        }
    }

    private func updateAvailability(_ available: Bool) async {
        await MainActor.run { LyricsState.shared.isAvailable = available }
    }

    private func resolveQuery(videoId: String) -> LyricsQuery? {
        let np = NowPlaying.shared

        let title: String
        let artist: String
        let album: String?
        let duration: TimeInterval

        if !np.title.isEmpty, !np.displayArtist.isEmpty {
            title = np.title
            artist = np.displayArtist
            album = np.albumTitle.isEmpty ? nil : np.albumTitle
            duration = np.duration
        } else if let song = np.queueSongs.first(where: { $0.videoId == videoId }) {
            title = song.title
            artist = song.artists.map(\.name).joined(separator: ", ")
            album = song.album?.isEmpty == false ? song.album : nil
            duration = TimeInterval(song.duration)
        } else {
            return nil
        }

        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return LyricsQuery(
            title: title,
            artist: artist,
            album: album,
            duration: duration > 0 ? duration : 0
        )
    }
}
