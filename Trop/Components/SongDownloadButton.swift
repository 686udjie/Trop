//
//  SongDownloadButton.swift
//  Trop
//
//  Created by 686udjie on 28/08/2026.
//

import SwiftUI

struct SongDownloadButton: View {
    let song: SongItem
    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        control(for: downloadManager.state(for: song.videoId))
            .frame(minWidth: 32, minHeight: 44)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func control(for state: DownloadManager.DownloadState) -> some View {
        switch state {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(.secondary)
        case .downloading:
            Color.clear
                .frame(minWidth: 32, minHeight: 44)
        case .notStarted, .failed:
            Button {
                Task { await downloadManager.download(song: song) }
            } label: {
                Image(systemName: "arrow.down")
                    .font(.body)
            }
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
    }
}

/// Full-cell progress bar used as a background/overlay on the row.
/// Fills from left to right with the accent color at low opacity while downloading.
struct DownloadCellProgressView: View {
    let song: SongItem
    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        let state = downloadManager.state(for: song.videoId)
        return GeometryReader { geo in
            if case .downloading(let fraction) = state {
                Color.accentColor.opacity(0.25)
                    .frame(
                        width: geo.size.width * CGFloat(min(max(fraction, 0), 1)),
                        height: geo.size.height
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state)
    }
}
