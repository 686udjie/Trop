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

        if np.videoId == videoId, !np.title.isEmpty, !np.displayArtist.isEmpty {
            title = np.title
            artist = np.displayArtist
            album = np.albumTitle.isEmpty ? nil : np.albumTitle
            duration = np.duration
        } else if let song = np.queueSongs.first(where: { $0.videoId == videoId }) {
            title = song.title
            artist = song.artists.map(\.name).joined(separator: ", ")
            album = song.album?.isEmpty == false ? song.album : nil
            let dur = song.duration > 0 ? song.duration : (DurationCache.get(videoId) ?? 0)
            duration = TimeInterval(dur)
        } else {
            return nil
        }

        guard !title.isEmpty, !artist.isEmpty else { return nil }
        let cleaned = cleanQuery(title: title, artist: artist, album: album)
        return LyricsQuery(
            title: cleaned.title,
            artist: cleaned.artist,
            album: cleaned.album,
            duration: duration > 0 ? duration : 0
        )
    }

    private func cleanQuery(title: String, artist: String, album: String?) -> (title: String, artist: String, album: String?) {
        let (extractedTitle, extractedArtist) = Self.extractArtistTitle(from: title, channelArtist: artist)
        let cleanedTitle = Self.cleanTitle(extractedTitle)
        let cleanedArtist = Self.cleanArtist(extractedArtist ?? artist)
        let cleanedAlbum = album.map { Self.cleanAlbum($0) }
        return (cleanedTitle, cleanedArtist, cleanedAlbum)
    }

    private static func extractArtistTitle(from rawTitle: String, channelArtist: String) -> (title: String, artist: String?) {
        guard isChannelLike(channelArtist) else { return (rawTitle, nil) }
        let separators = [" - ", " – ", " — "]
        for sep in separators {
            if let range = rawTitle.range(of: sep) {
                let left = String(rawTitle[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let right = String(rawTitle[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !left.isEmpty, !right.isEmpty else { break }
                // left = real artist, right = real title
                return (right, left)
            }
        }
        return (rawTitle, nil)
    }

    private static func isChannelLike(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard !lower.isEmpty else { return false }
        let channelWords = ["music", "channel", "official", "records", "record",
                           "tv", "studio", "entertainment", "4k", "中文", "古风",
                           "chinese", "ort", "ehp", "vip", "lyrics", "mv",
                           "topic", "vevo", "remix", "dj", "radio"]
        return channelWords.contains(where: { lower.contains($0) })
    }

    private static func cleanTitle(_ raw: String) -> String {
        var s = raw
        s = s.replacingOccurrences(of: #"【[^】]*】"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"「[^」]*」"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"『[^』]*』"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        for marker in ["|", "♪", "mv", "lyrics", "歌词", "動態", "动态", "official", "官方"] {
            if let r = s.range(of: marker, options: .caseInsensitive) {
                s = String(s[..<r.lowerBound])
                break
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanArtist(_ raw: String) -> String {
        let parts = raw
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { part -> String in
                var p = part
                if let range = p.range(of: " - ") {
                    p = String(p[..<range.lowerBound])
                }
                p = p.replacingOccurrences(of: " - Topic", with: "")
                p = p.replacingOccurrences(of: "-Topic", with: "")
                p = p.replacingOccurrences(of: "Topic", with: "")
                return p.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        return parts.joined(separator: ", ")
    }

    private static func cleanAlbum(_ raw: String) -> String {
        var s = raw
        s = s.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
