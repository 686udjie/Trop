//
//  SongMenuView.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import SwiftUI

struct SongMenuView: View {
    @Environment(SettingsStore.self) private var settings
    let songItem: SongItem
    let webUrl: String
    let artistBrowseId: String?
    let albumBrowseId: String?
    let onNavigate: (DetailRoute) -> Void

    @ObservedObject private var downloadManager = DownloadManager.shared

    private var downloadState: DownloadManager.DownloadState {
        downloadManager.state(for: songItem.videoId)
    }

    var body: some View {
        Menu {
            downloadActions

            Button {
                UIPasteboard.general.string = webUrl
            } label: {
                Label("Copy Link", systemImage: "link")
            }
            if let artistId = artistBrowseId {
                Button {
                    onNavigate(.artist(browseId: artistId))
                } label: {
                    Label("Go to Artist", systemImage: "music.mic")
                }
            }
            if let albumId = albumBrowseId {
                Button {
                    onNavigate(.album(browseId: albumId))
                } label: {
                    Label("Go to Album", systemImage: "record.circle")
                }
            }

        } label: {
            menuLabel
        }
        .menuOrder(.fixed)
    }

    @ViewBuilder
    private var downloadActions: some View {
        switch downloadState {
        case .downloading(let fraction):
            Button {} label: {
                Label("Downloading… \(Int(fraction * 100))%", systemImage: "arrow.down.circle")
            }
            .disabled(true)

        case .completed:
            Button {
                Task { await downloadManager.delete(videoId: songItem.videoId) }
            } label: {
                Label("Remove Download", systemImage: "trash")
            }

        case .failed(let message):
            Button {
                Task { await downloadManager.download(song: songItem) }
            } label: {
                Label("Retry Download", systemImage: "arrow.clockwise")
            }
            Button {} label: {
                Label(message, systemImage: "exclamationmark.triangle")
            }
            .disabled(true)

        case .notStarted:
            Button {
                Task { await downloadManager.download(song: songItem) }
            } label: {
                Label("Download", systemImage: "square.and.arrow.down")
            }
        }
    }

    @ViewBuilder
    private var menuLabel: some View {
        ZStack(alignment: .topTrailing) {
            Text("\u{22EE}")
                .font(.body.weight(.black))
                .foregroundStyle(settings.accentColor)

            if case .completed = downloadState {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(2)
                    .background(Circle().fill(settings.accentColor))
                    .offset(x: 4, y: -4)
            } else if case .downloading = downloadState {
                ProgressView()
                    .controlSize(.mini)
                    .offset(x: 6, y: -6)
            }
        }
    }
}
