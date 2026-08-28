//
//  PlaylistHeaderView.swift
//  Trop
//
//  Created by 686udjie on 28/08/2026.
//

import SwiftUI

struct PlaylistHeaderView: View {
    let title: String
    let subtitle: String?
    let thumbnailUrl: String?
    let thumbnails: [String]
    let songCount: Int
    let duration: Int
    let accentColor: Color
    let onPlay: () -> Void
    let onShuffle: () -> Void
    let onMore: (() -> Void)?

    init(
        title: String,
        subtitle: String? = nil,
        thumbnailUrl: String? = nil,
        thumbnails: [String] = [],
        songCount: Int,
        duration: Int,
        accentColor: Color = .accentColor,
        onPlay: @escaping () -> Void,
        onShuffle: @escaping () -> Void,
        onMore: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.thumbnailUrl = thumbnailUrl
        self.thumbnails = thumbnails
        self.songCount = songCount
        self.duration = duration
        self.accentColor = accentColor
        self.onPlay = onPlay
        self.onShuffle = onShuffle
        self.onMore = onMore
    }

    var body: some View {
        VStack(spacing: 14) {
            artwork
            textBlock
            if songCount > 0 {
                playbackControls
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
    }

    private var textBlock: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if songCount > 0 {
                Text(metadataLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 20) {
            Button(action: onShuffle) {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shuffle")

            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(accentColor))
                    .shadow(color: accentColor.opacity(0.4), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play all")

            if let onMore {
                Button(action: onMore) {
                    Text("\u{22EE}")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More options")
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var artwork: some View {
        if thumbnails.count >= 4 {
            artGrid
        } else if let url = thumbnailUrl ?? thumbnails.first {
            artSingle(url: url)
        } else {
            artPlaceholder
        }
    }

    private var artGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 2)
        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, url in
                AsyncImageView(url: url)
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .frame(width: 200, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
    }

    private func artSingle(url: String) -> some View {
        AsyncImageView(url: url)
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
    }

    private var artPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        accentColor.opacity(0.9),
                        accentColor.opacity(0.55),
                        Color.teal.opacity(0.65)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 200, height: 200)
            .overlay {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .symbolRenderingMode(.hierarchical)
            }
            .shadow(color: accentColor.opacity(0.35), radius: 16, y: 6)
    }

    private var metadataLine: String {
        var parts: [String] = []
        parts.append("\(songCount) \(songCount == 1 ? "song" : "songs")")
        if duration > 0 {
            parts.append(duration.formattedDuration)
        }
        return parts.joined(separator: " · ")
    }
}
