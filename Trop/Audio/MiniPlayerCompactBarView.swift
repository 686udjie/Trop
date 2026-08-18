//
//  MiniPlayerCompactBarView.swift
//  Trop
//
//  Created by 686udjie on 18/08/2026.
//

import SwiftUI

/// The slim full-width mini player bar shown while the content underneath is
/// scrolled down (mirrors LNPopup's compact bar): no artwork or title, just the
/// play/pause control and the bottom progress line. Tapping expands the player.
struct MiniPlayerCompactBarView: View {
    let onExpand: () -> Void

    private let player = PlayerController.shared
    @Bindable private var np = NowPlaying.shared

    private let barHeight: CGFloat = 40

    var body: some View {
        HStack {
            playPauseButton
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 20)
        }
        .frame(height: barHeight)
        .glassEffect(.regular, in: .capsule)
        .overlay(alignment: .bottom) { progressLine }
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture { onExpand() }
    }

    private var playPauseButton: some View {
        Button(action: { player.togglePlayPause() }) {
            Image(systemName: np.isPlaying ? "pause.fill" : "play.fill")
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(np.isPlaying ? "Pause" : "Play")
    }

    private var progressLine: some View {
        GeometryReader { geo in
            Capsule()
                .fill(.tint)
                .frame(width: geo.size.width * CGFloat(np.progress))
        }
        .frame(height: 1.5)
        .padding(.horizontal, 14)
        .padding(.bottom, 1)
        .allowsHitTesting(false)
    }
}