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
    var progress: Float = 0
    var isPopupOpen = false
    var thumbnailImage: Image?
    var thumbnailUIImage: UIImage?

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
    private var lockScreenUpdateCounter: Int = 0
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
        self.artist = artist ?? ""
        if let album {
            albumTitle = album
        }
        self.videoId = videoId
        self.isPlaying = true
        PlayerController.shared.setNowPlayingMetadata()
        DispatchQueue.main.async { [weak self] in
            self?.startTimer()
        }
        loadThumbnail(videoId: videoId)
    }

    func stopped(videoId: String?) {
        guard self.videoId == videoId else { return }
        if let skipTime = lastManualSkipTime, Date().timeIntervalSince(skipTime) < 2 {
            return
        }
        if hasNext {
            playNext(automatic: true)
        } else {
            isPlaying = false
            thumbnailImage = nil
            thumbnailUIImage = nil
            stopTimer()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    private func loadThumbnail(videoId: String) {
        let urlString = "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
        guard let url = URL(string: urlString) else {
            thumbnailImage = Image(systemName: "music.note")
            return
        }
        Task {
            do {
                let platformImage = try await ImagePipeline.shared.image(for: url)
                await MainActor.run {
                    thumbnailUIImage = platformImage
                    thumbnailImage = Image(uiImage: platformImage)
                    PlayerController.shared.setNowPlayingMetadata()
                }
            } catch {
                await MainActor.run {
                    thumbnailImage = Image(systemName: "music.note")
                }
            }
        }
    }

    private func startTimer() {
        stopTimer()
        lockScreenUpdateCounter = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            currentTime = PlayerController.shared.currentTime
            duration = PlayerController.shared.duration
            progress = duration > 0 ? Float(currentTime / duration) : 0
            isPlaying = PlayerController.shared.playState.value == .playing
            lockScreenUpdateCounter += 1
            if lockScreenUpdateCounter >= 8 {
                lockScreenUpdateCounter = 0
                PlayerController.shared.updateNowPlayingProgress()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
