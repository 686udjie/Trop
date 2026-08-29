//
//  DownloadedSongRow.swift
//  Trop
//
//  Created by 686udjie on 28/08/2026.
//

import SwiftUI

struct DownloadedSongRow: View {
    @Environment(SettingsStore.self) private var settings
    let song: SongItem
    var onPlay: () -> Void
    var onNavigate: (DetailRoute) -> Void

    @State private var showSongMenu = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncImageView(url: song.thumbnailUrl)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(song.artistNamesDisplay)
                    if song.duration > 0 {
                        Text("•")
                        Text(song.duration.formattedDuration)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                SongLikeButton(song: song)
                SongDownloadButton(song: song)
                Button {
                    showSongMenu = true
                } label: {
                    Text("\u{22EE}")
                        .font(.body.weight(.black))
                        .foregroundStyle(settings.accentColor)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More")
            }
            .sheet(isPresented: $showSongMenu) {
                SongMenuSheet(song: song, onNavigate: onNavigate)
            }
        }
        .background(DownloadCellProgressView(song: song))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onPlay()
        }
    }
}
