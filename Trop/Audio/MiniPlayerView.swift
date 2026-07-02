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
                Button {} label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: playState == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                }

                Button {} label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
            }
            .foregroundStyle(.primary)

            Spacer()
        }
        .popupTitle(verbatim: np.title, subtitle: np.artist.isEmpty ? nil : np.artist)
        .popupImage(np.thumbnailImage)
        .popupProgress(progress)
        .popupBarCustomizer { bar in
            bar.imageView.contentMode = .scaleAspectFill
            bar.imageView.cornerRadius = 6
        }
        .popupBarTrailingItems {
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: playState == .playing ? "pause.fill" : "play.fill")
            }
        }
        .onReceive(timer) { _ in
            currentTime = player.currentTime
            duration = player.duration
            progress = player.duration > 0 ? Float(player.currentTime / player.duration) : 0
            playState = player.playState.value
        }
    }

    private var isPlaying: Bool {
        playState == .playing
    }

    private var artwork: some View {
        (np.thumbnailImage ?? Image(systemName: "music.note"))
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private var progressSlider: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(
                get: { progress },
                set: { player.seek(to: TimeInterval($0) * player.duration) }
            ))
            .tint(.primary)

            HStack {
                Text(formattedTime(currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedTime(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 40)
    }

    private func formattedTime(_ time: TimeInterval) -> String {
        guard !time.isNaN, !time.isInfinite else { return "0:00" }
        let total = Int(time)
        let m = total / 60
        let s = total % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}
