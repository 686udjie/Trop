//
//  ActiveDownloadRow.swift
//  Trop
//
//  Created by 686udjie on 28/08/2026.
//

import SwiftUI

struct ActiveDownloadRow: View {
    @Environment(SettingsStore.self) private var settings
    let videoId: String
    let progress: Double

    @State private var title = "Downloading…"
    @State private var artist = ""
    @State private var thumbnailUrl: String?

    var body: some View {
        HStack(spacing: 14) {
            thumbnailView
            infoStack
            Spacer(minLength: 0)
            Text("\(Int(progress * 100))%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(settings.accentColor)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .task { await loadMetadata() }
    }

    private var thumbnailView: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let thumbnailUrl {
                    AsyncImageView(url: thumbnailUrl)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [settings.accentColor.opacity(0.5), settings.accentColor.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Image(systemName: "music.note")
                                .foregroundStyle(settings.accentColor.opacity(0.8))
                        }
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            downloadRing
                .offset(x: 4, y: 4)
        }
    }

    private var infoStack: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(artist.isEmpty ? "Preparing download…" : artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ProgressView(value: progress)
                .tint(settings.accentColor)
        }
    }

    private var downloadRing: some View {
        ZStack {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 22, height: 22)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(settings.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 18, height: 18)
            Image(systemName: "arrow.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(settings.accentColor)
        }
    }

    private func loadMetadata() async {
        if let entity = try? await DatabaseService.shared.fetchOne(SongEntity.self, key: videoId) {
            title = entity.title
            artist = entity.artistName ?? ""
            thumbnailUrl = entity.thumbnailUrl
            return
        }
        if let entity = try? await DatabaseService.shared.fetchOne(DownloadedTrackEntity.self, key: videoId) {
            title = entity.title
            artist = entity.artist
            thumbnailUrl = entity.thumbnailUrl
        }
    }
}
