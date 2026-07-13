//
//  NowPlaying.swift
//  Trop
//
//  Created by 686udjie on 2/07/2026.
//

import Foundation
import Observation
import Combine
import Nuke
import SwiftUI
import MediaPlayer

@Observable
final class NowPlaying {
    static let shared = NowPlaying()

    var title = ""
    var artist = ""
    var albumTitle = ""
    var videoId: String?
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var progress: Float {
        duration > 0 ? Float(currentTime / duration) : 0
    }
    var isPopupOpen = false
    var thumbnailImage: Image?
    var thumbnailUIImage: UIImage?
    var thumbnailVersion = 0
    var dominantColors: [Color] = [Color(red: 0.15, green: 0.15, blue: 0.2), Color(red: 0.05, green: 0.05, blue: 0.08)]

    var accentColor: Color? {
        guard videoId != nil, let primary = dominantColors.first else { return nil }
        return primary
    }

    var queueSongs: [SongItem] = []
    var queueIndex = 0

    var hasNext: Bool {
        queueIndex + 1 < queueSongs.count
    }

    var hasPrevious: Bool {
        queueIndex > 0
    }

    var isBarPresented: Bool {
        videoId != nil
    }

    private var timer: Timer?
    var lastManualSkipTime: Date?

    private init() {}

    func setQueue(_ songs: [SongItem], startIndex: Int) {
        queueSongs = songs
        queueIndex = startIndex
    }

    func playNext(automatic: Bool = false) {
        guard hasNext else { return }
        if !automatic { lastManualSkipTime = Date() }
        queueIndex += 1
        let song = queueSongs[queueIndex]
        let displayArtist = song.artists.map(\.name).joined(separator: ", ")
        update(title: song.title, artist: displayArtist, videoId: song.videoId, album: song.album)
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
            } catch {
                print("[NowPlaying] playNext failed: \(error)")
            }
        }
    }

    func playPrevious() {
        guard hasPrevious else { return }
        lastManualSkipTime = Date()
        queueIndex -= 1
        let song = queueSongs[queueIndex]
        let displayArtist = song.artists.map(\.name).joined(separator: ", ")
        update(title: song.title, artist: displayArtist, videoId: song.videoId, album: song.album)
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
            } catch {
                print("[NowPlaying] playPrevious failed: \(error)")
            }
        }
    }

    func update(title: String, artist: String?, videoId: String, album: String? = nil) {
        self.title = title
        self.artist = cleanArtist(artist ?? "")
        if let album {
            albumTitle = album
        }
        self.videoId = videoId
        self.isPlaying = true
        currentTime = 0
        duration = 0
        PlayerController.shared.setNowPlayingMetadata()
        DispatchQueue.main.async { [weak self] in
            self?.startTimer()
        }
        loadThumbnail(videoId: videoId)
        preloadNextTrack()
    }

    func stopped(videoId: String?, isEof: Bool = true) {
        guard self.videoId == videoId else { return }
        if let skipTime = lastManualSkipTime, Date().timeIntervalSince(skipTime) < 2 {
            return
        }
        guard isEof else {
            isPlaying = false
            return
        }
        currentTime = duration
        if hasNext {
            playNext(automatic: true)
        } else {
            isPlaying = false
            thumbnailImage = nil
            thumbnailUIImage = nil
            Task { @MainActor in
                self.updateDominantColors(from: nil)
            }
            stopTimer()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    private var lastLoadedVideoId: String?

    private func loadThumbnail(videoId: String) {
        guard videoId != lastLoadedVideoId else { return }
        lastLoadedVideoId = videoId
        let urlString = "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
        guard let url = URL(string: urlString) else {
            thumbnailImage = Image(systemName: "music.note")
            Task { @MainActor in
                self.updateDominantColors(from: nil)
            }
            return
        }
        Task {
            do {
                let platformImage = try await ImagePipeline.shared.image(for: url)
                await MainActor.run {
                    thumbnailUIImage = platformImage
                    thumbnailImage = Image(uiImage: platformImage)
                    thumbnailVersion &+= 1
                    updateDominantColors(from: platformImage)
                    PlayerController.shared.setNowPlayingMetadata()
                }
            } catch {
                await MainActor.run {
                    thumbnailImage = Image(systemName: "music.note")
                    thumbnailVersion &+= 1
                    updateDominantColors(from: nil)
                }
            }
        }
    }

    private func preloadNextTrack() {
        guard hasNext else { return }
        let nextId = queueSongs[queueIndex + 1].videoId
        Task {
            do {
                _ = try await PlaybackManager.shared.resolve(videoId: nextId)
                print("[NowPlaying] Pre-resolved next track: \(nextId)")
            } catch {
                print("[NowPlaying] Pre-resolve failed: \(error)")
            }
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            currentTime = PlayerController.shared.currentTime
            duration = PlayerController.shared.duration
            isPlaying = PlayerController.shared.playState.value == .playing
            PlayerController.shared.updateNowPlayingProgress()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    private func updateDominantColors(from uiImage: UIImage?) {
        guard let uiImage = uiImage else {
            self.dominantColors = [Color(red: 0.15, green: 0.15, blue: 0.2), Color(red: 0.05, green: 0.05, blue: 0.08)]
            return
        }
        self.dominantColors = uiImage.extractDominantColors()
    }

    private func cleanArtist(_ name: String) -> String {
        cleanArtistDisplay(name)
    }
}

// MARK: - Module-level artist name cleaner

func cleanArtistDisplay(_ name: String) -> String {
    var tempName = name

    // Strip " - Topic"
    for suffix in [" - Topic", " - topic", " - TOPIC"] {
        if tempName.lowercased().hasSuffix(suffix.lowercased()) {
            tempName = String(tempName.dropLast(suffix.count))
        }
    }

    // Strip trailing year "(2025)" / "[2025]"
    if let r = try? NSRegularExpression(pattern: "\\s*[\\(\\[]\\d{4}[\\)\\]]\\s*$") {
        tempName = r.stringByReplacingMatches(
            in: tempName,
            range: NSRange(tempName.startIndex..., in: tempName),
            withTemplate: ""
        )
    }

    // Split on commas, ampersands, and bullet separators (•, ·, |) then drop junk segments
    let separatorSet = CharacterSet(charactersIn: ",&•·|")
    let parts = tempName
        .components(separatedBy: separatorSet)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    let cleanParts = parts.filter { !_isJunkArtistSegment($0) }
    if cleanParts.isEmpty {
        return tempName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return cleanParts.joined(separator: ", ")
}

private func _isJunkArtistSegment(_ segment: String) -> Bool {
    let lower = segment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if lower.isEmpty || lower == "•" || lower == "·" { return true }

    let junkLabels: Set<String> = [
        "song", "video", "track", "music", "podcast", "episode",
        "album", "playlist", "released", "year", "plays", "views",
        "downloads", "listeners", "subscribers", "watchers", "likes"
    ]
    if junkLabels.contains(lower) { return true }

    let patterns = [
        // Number optionally followed by K/M/B/T and an optional metric word
        "^[\\d,\\.]+[KMBT]?\\s*(views|downloads|listeners|subscribers|plays|watchers|likes?)?$",
        "^\\d{4}$",              // bare year
        "^[\\d,\\.\\s]+[KMBT]?$" // purely numeric / abbreviated counts
    ]
    for pattern in patterns {
        if lower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { return true }
    }
    return false
}
