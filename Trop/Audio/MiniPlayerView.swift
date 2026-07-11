//
//  MiniPlayerView.swift
//  Trop
//
//  Created by 686udjie on 2/07/2026.
//

import SwiftUI
import LNPopupUI

struct MiniPlayerView: View {
    private let player = PlayerController.shared
    private let np = NowPlaying.shared

    @State private var editingProgress: Float = 0
    @State private var isEditingSlider = false
    @State private var activeItemId = ""

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
                Button { np.playPrevious() } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .disabled(!np.hasPrevious)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: np.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                }

                Button { np.playNext() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .disabled(!np.hasNext)
            }
            .foregroundStyle(.blue)

            Spacer()
        }
        .overlay(MiniPlayerPopupItems(
            queueSongs: np.queueSongs,
            videoId: np.videoId,
            thumbnailImage: np.thumbnailImage,
            thumbnailVersion: np.thumbnailVersion,
            activeItemId: $activeItemId
        ).equatable())
        .popupBarCustomizer { bar in
            bar.imageView.contentMode = .scaleAspectFill
            bar.imageView.cornerRadius = 6
        }
        .onChange(of: activeItemId) { _, newId in
            guard newId != np.videoId else { return }
            guard let idx = np.queueSongs.firstIndex(where: { $0.videoId == newId }) else { return }
            np.lastManualSkipTime = Date()
            np.queueIndex = idx
            let song = np.queueSongs[idx]
            np.update(title: song.title, artist: song.artists.map(\.name).joined(separator: ", "), videoId: song.videoId)
            Task { try? await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId) }
        }
        .onChange(of: np.videoId) { _, newId in activeItemId = newId ?? "" }
        .onChange(of: np.queueSongs.count) { _, _ in activeItemId = np.videoId ?? "" }
    }

    private var artwork: some View {
        (np.thumbnailImage ?? Image(systemName: "music.note"))
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private var progressSlider: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(
                get: { isEditingSlider ? editingProgress : np.progress },
                set: { editingProgress = $0 }
            ), onEditingChanged: { editing in
                if editing {
                    editingProgress = np.progress
                } else {
                    player.seek(to: TimeInterval(editingProgress) * np.duration)
                    player.updateNowPlayingProgress()
                }
                isEditingSlider = editing
            })
            .tint(.blue)

            HStack {
                Text(timeString(np.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timeString(np.duration))
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

private struct MiniPlayerPopupItems: View, Equatable {
    let queueSongs: [SongItem]
    let videoId: String?
    let thumbnailImage: Image?
    let thumbnailVersion: Int
    @Binding var activeItemId: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.videoId == rhs.videoId &&
        lhs.queueSongs.map(\.videoId) == rhs.queueSongs.map(\.videoId) &&
        lhs.thumbnailVersion == rhs.thumbnailVersion
    }

    var body: some View {
        Color.clear
            .popupItems(selection: $activeItemId) {
                for song in queueSongs {
                    PopupItem(
                        id: song.videoId,
                        verbatimTitle: song.title,
                        verbatimSubtitle: song.artists.map(\.name).joined(separator: ", "),
                        image: thumbnailImage,
                        progress: 0
                    ) {
                        ToolbarItemGroup(placement: .popupBar) {
                            Button(action: { PlayerController.shared.togglePlayPause() }) {
                                Image(systemName: "pause.fill")
                            }
                        }
                    }
                }
            }
    }
}
