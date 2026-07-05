//
//  MiniPlayerView.swift
//  Trop
//
//  Created by 686udjie on 2/07/2026.
//

import SwiftUI
import LNPopupUI
import Combine

struct MiniPlayerView: View {
    private let player = PlayerController.shared
    private let np = NowPlaying.shared

    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var progress: Float = 0
    @State private var playState: PlayerController.State = .stopped
    @State private var isEditingSlider = false
    @State private var activeItemId = ""

    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            artwork
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(radius: 8)
                .padding(.horizontal, 40)

            VStack(spacing: 6) {
                Text(np.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)

                if !np.artist.isEmpty {
                    Text(np.artist)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            progressSlider

            HStack(spacing: 40) {
                Button { player.stop(); np.playPrevious() } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .disabled(!np.hasPrevious)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: playState == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                }

                Button { player.stop(); np.playNext() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .disabled(!np.hasNext)
            }
            .foregroundStyle(.blue)

            Spacer()
        }
        .popupBarCustomizer { bar in
            bar.imageView.contentMode = .scaleAspectFill
            bar.imageView.cornerRadius = 6
        }
        .popupItems(selection: $activeItemId) {
            for song in np.queueSongs {
                PopupItem(id: song.videoId, verbatimTitle: song.title, verbatimSubtitle: song.artists.map(\.name).joined(separator: ", "), image: np.thumbnailImage, progress: progress) {
                    ToolbarItemGroup(placement: .popupBar) {
                        Button {
                            player.togglePlayPause()
                        } label: {
                            Image(systemName: playState == .playing ? "pause.fill" : "play.fill")
                        }
                    }
                }
            }
        }
        .onChange(of: activeItemId) { _, newId in
            guard newId != np.videoId else { return }
            guard let idx = np.queueSongs.firstIndex(where: { $0.videoId == newId }) else { return }
            np.queueIndex = idx
            let song = np.queueSongs[idx]
            np.update(title: song.title, artist: song.artists.map(\.name).joined(separator: ", "), videoId: song.videoId)
            Task { try? await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId) }
        }
        .onChange(of: np.videoId) { _, newId in activeItemId = newId ?? "" }
        .onChange(of: np.queueSongs.count) { _, _ in activeItemId = np.videoId ?? "" }
        .onReceive(timer) { _ in
            guard !isEditingSlider else { return }
            currentTime = player.currentTime
            duration = player.duration
            progress = player.duration > 0 ? Float(player.currentTime / player.duration) : 0
            playState = player.playState.value
        }
    }

    private var artwork: some View {
        (np.thumbnailImage ?? Image(systemName: "music.note"))
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private var progressSlider: some View {
        VStack(spacing: 4) {
            Slider(value: $progress, onEditingChanged: { editing in
                if !editing { player.seek(to: TimeInterval(progress) * player.duration) }
                isEditingSlider = editing
            })
            .tint(.blue)

            HStack {
                Text(timeString(currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timeString(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 40)
    }

    private func timeString(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00" }
        return "\(Int(t) / 60):\(String(format: "%02d", Int(t) % 60))"
    }
}
