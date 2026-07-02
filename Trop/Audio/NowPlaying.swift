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

@Observable
final class NowPlaying {
    static let shared = NowPlaying()

    var title = ""
    var artist = ""
    var videoId: String?
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var progress: Float = 0
    var isPopupOpen = false
    var thumbnailImage: Image?

    var isBarPresented: Bool {
        videoId != nil
    }

    private var timer: Timer?

    private init() {}

    func update(title: String, artist: String?, videoId: String) {
        self.title = title
        self.artist = artist ?? ""
        self.videoId = videoId
        self.isPlaying = true
        startTimer()
        loadThumbnail(videoId: videoId)
    }

    func stopped() {
        isPlaying = false
        videoId = nil
        thumbnailImage = nil
        stopTimer()
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
                    thumbnailImage = Image(uiImage: platformImage)
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            currentTime = PlayerController.shared.currentTime
            duration = PlayerController.shared.duration
            progress = duration > 0 ? Float(currentTime / duration) : 0
            isPlaying = PlayerController.shared.playState.value == .playing
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
