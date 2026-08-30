//
//  NowPlaying.swift
//  Trop
//
//  Created by 686udjie on 2/07/2026.
//

import AVFoundation
import Foundation
import Observation
import Combine
import Nuke
import SwiftUI
import MediaPlayer

@Observable
@MainActor
final class NowPlaying {
    static let shared = NowPlaying()

    var title = ""
    var artist = ""
    var albumTitle = ""
    var videoId: String?
    var artists: [YTArtist] = []
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var progress: Float {
        duration > 0 ? Float(currentTime / duration) : 0
    }
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

    var isShuffleOn = false
    var isRepeatOn = false

    var hasVideo: Bool = false
    var isVideoMode: Bool = false
    var musicVideoType: String?

    private var originalQueue: [SongItem]?
    private var originalIndex: Int = 0

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
    private var isResolvingNext = false
    /// Timestamps of the last mid-play failure per videoId, to bound retries.
    private var lastFailureAt: [String: Date] = [:]

    private static let queueKey = "nowPlaying.queue"
    private static let queueIndexKey = "nowPlaying.queueIndex"
    private static let shuffleKey = "nowPlaying.shuffle"
    private static let repeatKey = "nowPlaying.repeat"

    private init() {
        restoreQueueIfNeeded()
    }

    deinit {
        Task { @MainActor [weak self] in self?.stopTimer() }
    }

    // MARK: - Persistent queue

    private func restoreQueueIfNeeded() {
        guard SettingsStore.shared.persistQueue,
              let data = UserDefaults.standard.data(forKey: Self.queueKey),
              let songs = try? JSONDecoder().decode([SongItem].self, from: data),
              !songs.isEmpty else { return }
        queueSongs = songs
        queueIndex = min(UserDefaults.standard.integer(forKey: Self.queueIndexKey), songs.count - 1)
        isShuffleOn = UserDefaults.standard.bool(forKey: Self.shuffleKey)
        isRepeatOn = UserDefaults.standard.bool(forKey: Self.repeatKey)
        if !queueSongs.isEmpty {
            queueIndex = max(0, queueIndex)
        }
    }

    func persistQueueState() {
        guard SettingsStore.shared.persistQueue, !queueSongs.isEmpty else { return }
        if let data = try? JSONEncoder().encode(queueSongs) {
            UserDefaults.standard.set(data, forKey: Self.queueKey)
        }
        UserDefaults.standard.set(queueIndex, forKey: Self.queueIndexKey)
        UserDefaults.standard.set(isShuffleOn, forKey: Self.shuffleKey)
        UserDefaults.standard.set(isRepeatOn, forKey: Self.repeatKey)
    }

    func setQueue(_ songs: [SongItem], startIndex: Int) {
        queueSongs = songs
        queueIndex = min(max(startIndex, 0), max(songs.count - 1, 0))
        originalQueue = nil
        isShuffleOn = false
        persistQueueState()
    }

    /// Ensures `queueIndex` points at a valid entry
    func repairQueueIndex() {
        if queueSongs.isEmpty {
            queueIndex = 0
            return
        }
        if let videoId, let idx = queueSongs.firstIndex(where: { $0.videoId == videoId }) {
            queueIndex = idx
        } else {
            queueIndex = min(max(queueIndex, 0), queueSongs.count - 1)
        }
    }

    func upcomingSongs(prefixLimit: Int? = nil) -> [SongItem] {
        let next = queueIndex + 1
        guard queueSongs.indices.contains(next) else { return [] }
        let rest = Array(queueSongs[next...])
        guard let prefixLimit else { return rest }
        return Array(rest.prefix(prefixLimit))
    }

    /// Shuffles upcoming songs, keeping the current one; tapping again re-shuffles.
    func shuffleQueue() {
        guard queueSongs.count > 1 else {
            isShuffleOn = true
            return
        }
        if originalQueue == nil {
            originalQueue = queueSongs
            originalIndex = queueIndex
        }
        let current = queueSongs[queueIndex]
        var rest = Array(queueSongs[(queueIndex + 1)...])
        rest.shuffle()
        queueSongs = [current] + rest
        queueIndex = 0
        isShuffleOn = true
        persistQueueState()
    }

    /// Restore the original (unshuffled) queue order.
    func disableShuffle() {
        guard queueSongs.indices.contains(queueIndex) else { return }
        if let orig = originalQueue {
            let currentVideoId = queueSongs[queueIndex].videoId
            queueSongs = orig
            queueIndex = orig.firstIndex(where: { $0.videoId == currentVideoId }) ?? originalIndex
        }
        originalQueue = nil
        isShuffleOn = false
        persistQueueState()
    }

    func moveQueueSongs(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty, queueSongs.indices.contains(source.first ?? -1) else { return }
        queueSongs.move(fromOffsets: source, toOffset: destination)
        repairQueueIndex()
        persistQueueState()
    }

    func repeatCurrent() {
        guard queueSongs.indices.contains(queueIndex) else { return }
        isResolvingNext = true
        let song = queueSongs[queueIndex]
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
            } catch {
                Log.nowPlaying.error("repeatCurrent failed: \(error)")
                if self.videoId == song.videoId {
                    isPlaying = false
                }
            }
            isResolvingNext = false
            isRepeatOn = false
        }
        persistQueueState()
    }

    func playNext(automatic: Bool = false) {
        guard hasNext else { return }
        guard !isResolvingNext else { return }
        if !automatic { lastManualSkipTime = Date() }
        isResolvingNext = true
        queueIndex += 1
        let song = queueSongs[queueIndex]
        let displayArtist = song.artists.map(\.name).joined(separator: ", ")
        update(title: song.title, artist: displayArtist, videoId: song.videoId, album: song.album, artists: song.artists)
        persistQueueState()
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
            } catch {
                Log.nowPlaying.error("playNext failed: \(error)")
                if self.videoId == song.videoId {
                    isPlaying = false
                }
            }
            isResolvingNext = false
        }
    }

    func playPrevious() {
        guard hasPrevious else { return }
        guard !isResolvingNext else { return }
        lastManualSkipTime = Date()
        isResolvingNext = true
        queueIndex -= 1
        let song = queueSongs[queueIndex]
        let displayArtist = song.artists.map(\.name).joined(separator: ", ")
        update(title: song.title, artist: displayArtist, videoId: song.videoId, album: song.album, artists: song.artists)
        persistQueueState()
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId)
            } catch {
                Log.nowPlaying.error("playPrevious failed: \(error)")
            }
            isResolvingNext = false
        }
    }

    func update(title: String, artist: String?, videoId: String, album: String? = nil, artists: [YTArtist] = []) {
        self.isPlaying = true
        self.title = title
        self.artists = artists
        self.artist = cleanArtist(artist ?? "")
        if let album {
            albumTitle = album
        }
        self.videoId = videoId
        self.hasVideo = false
        self.isVideoMode = false
        startTimer()
        loadThumbnail(videoId: videoId)
        preloadNextTrack()
        notifyIntegrationsTrackChanged()
    }

    /// Updates video availability from `musicVideoType` and/or `hasVideoContent`.
    func updateVideoAvailability(musicVideoType: String? = nil, hasVideoContent: Bool = false) {
        if let musicVideoType {
            self.musicVideoType = musicVideoType
        }
        let typeHasVideo = musicVideoType != nil &&
            musicVideoType != "MUSIC_VIDEO_TYPE_ATV" &&
            musicVideoType != "MUSIC_VIDEO_TYPE_PODCAST_EPISODE"
        let hasVideo = typeHasVideo || hasVideoContent
        self.hasVideo = hasVideo
        if hasVideo {
            PlayerController.shared.preloadVideoURL()
        }
    }

    /// Pre-warms artwork for the previous and upcoming songs so swiping the
    /// mini player bar shows their art instantly.
    func preloadNeighborArtwork() {
        var urls = upcomingSongs(prefixLimit: 3)
            .compactMap(\.thumbnailUrl)
            .compactMap { URL(string: $0) }
        let neighborIds = queueSongs.indices.compactMap { index -> String? in
            guard index == queueIndex - 1 || (index > queueIndex && index <= queueIndex + 3) else { return nil }
            return queueSongs[index].videoId
        }
        urls.append(contentsOf: neighborIds.compactMap { URL(string: Self.artworkURL(for: $0)) })
        guard !urls.isEmpty else { return }
        Task { await ImagePreloader.shared.append(urls) }
    }

    /// Artist string from `artists`, falling back to `artist`.
    var displayArtist: String {
        let fromArray = artistDisplayString(from: artists)
        if !fromArray.isEmpty { return fromArray }
        return artist
    }

    func stopped(videoId: String?, isEof: Bool = true) {
        guard self.videoId == videoId else { return }
        if let skipTime = lastManualSkipTime, Date().timeIntervalSince(skipTime) < 2, isResolvingNext {
            return
        }
        guard isEof else {
            recoverFromPlaybackFailure(videoId: videoId)
            return
        }
        currentTime = duration
        if isRepeatOn {
            repeatCurrent()
            return
        }
        if hasNext {
            playNext(automatic: true)
        } else if SettingsStore.shared.autoplaySimilar, let endedVideoId = videoId {
            autoplaySimilar(from: endedVideoId)
        } else {
            // End of queue, pause but keep the last song shown in the player.
            isPlaying = false
            stopTimer()
            PlayerController.shared.updateNowPlayingProgress()
        }
    }

    /// Continues playback with a radio queue built from the last song when the
    /// queue runs out and "Autoplay Similar" is enabled.
    private func autoplaySimilar(from videoId: String) {
        let lastSong = queueSongs.indices.contains(queueIndex) ? queueSongs[queueIndex] : nil
        Task {
            do {
                let radio = try await PersonalizationService.shared.fetchRadio(videoId: videoId)
                var songs = radio.songs
                if let lastSong, songs.first?.videoId != lastSong.videoId {
                    songs = [lastSong] + songs
                }
                guard !songs.isEmpty else {
                    isPlaying = false
                    return
                }
                self.queueSongs = songs
                self.queueIndex = 0
                self.isShuffleOn = false
                self.playNext(automatic: true)
            } catch {
                Log.nowPlaying.error("Autoplay similar failed: \(error)")
                isPlaying = false
            }
        }
    }

    /// A stream that died mid-play (not EOF, not a manual skip): drop the
    /// possibly-expired cached URL and re-resolve once. Repeated failures for
    /// the same video are only retried after a cooldown to avoid a loop.
    private func recoverFromPlaybackFailure(videoId: String?) {
        guard let videoId else {
            isPlaying = false
            return
        }
        PlayerController.shared.handleVideoStreamFailure()
        if let last = lastFailureAt[videoId], Date().timeIntervalSince(last) < 30 {
            isPlaying = false
            return
        }
        lastFailureAt[videoId] = Date()
        isPlaying = false
        Log.nowPlaying.notice("Stream failed mid-play, re-resolving \(videoId)")
        Task {
            await PlayerConfigStore.shared.notifyStreamRejection()
            await StreamCache.shared.remove(videoId: videoId)
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: videoId)
            } catch {
                Log.nowPlaying.error("Mid-play recovery failed: \(error)")
                if self.videoId == videoId {
                    isPlaying = false
                }
            }
        }
    }

    static func artworkURL(for videoId: String) -> String {
        "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
    }

    private var lastLoadedVideoId: String?

    private func loadThumbnail(videoId: String) {
        guard videoId != lastLoadedVideoId else { return }
        lastLoadedVideoId = videoId

        Task {
            // For downloaded songs, try to extract embedded artwork from the local file first.
            if let localURL = await DownloadManager.shared.localURL(for: videoId) {
                loadArtworkFromLocalFile(localURL, videoId: videoId)
                return
            }
            loadThumbnailFromCDN(videoId: videoId)
        }
    }

    private func loadArtworkFromLocalFile(_ fileURL: URL, videoId: String) {
        Task {
            let asset = AVURLAsset(url: fileURL)
            let metadata = try? await asset.load(.metadata)
            var artworkImage: UIImage?
            if let metadata {
                for item in metadata {
                    if let data = try? await item.load(.dataValue),
                       let image = UIImage(data: data) {
                        artworkImage = image
                        break
                    }
                }
            }

            await MainActor.run {
                guard lastLoadedVideoId == videoId else { return }
                if let artworkImage {
                    let cropped = artworkImage.centerCroppedSquare()
                    thumbnailUIImage = cropped
                    thumbnailImage = Image(uiImage: cropped)
                    thumbnailVersion &+= 1
                    updateDominantColors(from: cropped)
                    PlayerController.shared.updateNowPlayingArtwork()
                } else {
                    loadThumbnailFromCDN(videoId: videoId)
                }
            }
        }
    }

    private func loadThumbnailFromCDN(videoId: String) {
        let urlString = Self.artworkURL(for: videoId)
        guard let url = URL(string: urlString) else {
            thumbnailUIImage = nil
            thumbnailImage = Image(systemName: "music.note")
            thumbnailVersion &+= 1
            updateDominantColors(from: nil)
            return
        }

        if let cached = ImagePipeline.shared.cache.cachedImage(for: ImageRequest(url: url), caches: .all)?.image {
            let cropped = cached.centerCroppedSquare()
            thumbnailUIImage = cropped
            thumbnailImage = Image(uiImage: cropped)
            thumbnailVersion &+= 1
            updateDominantColors(from: cropped)
            PlayerController.shared.updateNowPlayingArtwork()
            return
        }

        thumbnailImage = nil
        Task {
            do {
                let platformImage = try await ImagePipeline.shared.image(for: url)
                let cropped = platformImage.centerCroppedSquare()
                await MainActor.run {
                    thumbnailUIImage = cropped
                    thumbnailImage = Image(uiImage: cropped)
                    thumbnailVersion &+= 1
                    updateDominantColors(from: cropped)
                    PlayerController.shared.updateNowPlayingArtwork()
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
                Log.nowPlaying.debug("Pre-resolved next track: \(nextId)")
            } catch {
                Log.nowPlaying.error("Pre-resolve failed: \(error)")
            }
        }
    }

    private func startTimer() {
        stopTimer()
        // Add to `.common` so progress keeps updating while the user scrolls
        // or drags the slider (the default mode pauses the timer).
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.timerTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @MainActor
    private func timerTick() {
        currentTime = PlayerController.shared.currentTime
        duration = PlayerController.shared.duration
        PlayerController.shared.updateNowPlayingProgress()
        notifyIntegrationsProgress()
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

/// Builds a clean, comma-separated artist string from an artist array, dropping
/// names that clean down to empty (junk/blank entries) so no dangling separator
/// is left behind.
func artistDisplayString(from artists: [YTArtist]) -> String {
    artists
        .map { cleanArtistDisplay($0.name) }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
}

func cleanArtistDisplay(_ name: String) -> String {
    var tempName = name

    // Strip " - Topic"
    for suffix in [" - Topic", " - topic", " - TOPIC"] where tempName.lowercased().hasSuffix(suffix.lowercased()) {
        tempName = String(tempName.dropLast(suffix.count))
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
        return ""
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
    for pattern in patterns where lower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
        return true
    }
    return false
}
