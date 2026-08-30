//
//  PlaylistMoreSheet.swift
//  Trop
//
//  Created by 686udjie on 28/08/2026.
//

import SwiftUI

struct PlaylistMoreSheet: View {
    let playlist: PlaylistDetailInfo
    var onSync: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.settingsStore) private var settings
    @State private var showEditAlert = false
    @State private var editedName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    menuCard {
                        menuRow(
                            icon: "pencil",
                            title: "Edit",
                            subtitle: "Edit playlist"
                        ) {
                            editedName = playlist.title
                            showEditAlert = true
                        }
                        Divider()
                        menuRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Sync",
                            subtitle: "Sync this playlist with YouTube Music"
                        ) {
                            onSync?()
                            dismiss()
                        }
                        Divider()
                        menuRow(
                            icon: "list.bullet",
                            title: "Add to Queue",
                            subtitle: "Add to the end of the queue"
                        ) {
                            addToQueue()
                            dismiss()
                        }
                        Divider()
                        menuRow(
                            icon: "square.and.arrow.down",
                            title: "Download",
                            subtitle: "Download all songs for offline playback"
                        ) {
                            downloadAll()
                            dismiss()
                        }
                        Divider()
                        menuRow(
                            icon: "square.and.arrow.up",
                            title: "Share",
                            subtitle: "Share this playlist with others"
                        ) {
                            share()
                            dismiss()
                        }
                        Divider()
                        menuRow(
                            icon: "trash",
                            title: "Delete",
                            subtitle: "Remove all downloads",
                            destructive: true
                        ) {
                            deleteAllDownloads()
                            dismiss()
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .alert("Rename Playlist", isPresented: $showEditAlert) {
            TextField("Playlist name", text: $editedName)
            Button("Rename") { renamePlaylist() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Menu Row

    private func menuRow(
        icon: String,
        title: String,
        subtitle: String? = nil,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            menuRowLabel(icon: icon, title: title, subtitle: subtitle, destructive: destructive)
        }
        .buttonStyle(.plain)
    }

    private func menuRowLabel(
        icon: String,
        title: String,
        subtitle: String? = nil,
        destructive: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(destructive ? Color.red : settings.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(destructive ? Color.red : Color.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Card

    @ViewBuilder
    private func menuCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Actions

    private func renamePlaylist() {
        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != playlist.title else { return }
        Task {
            try? await MutationService.shared.renamePlaylist(
                playlistId: playlist.playlistId,
                newName: name
            )
        }
    }

    private func addToQueue() {
        let np = NowPlaying.shared
        np.queueSongs.append(contentsOf: playlist.songs)
        np.persistQueueState()
    }

    private func downloadAll() {
        for song in playlist.songs {
            Task { await DownloadManager.shared.download(song: song) }
        }
    }

    private func share() {
        let urlString = "https://music.youtube.com/playlist?list=\(playlist.playlistId)"
        guard let url = URL(string: urlString) else { return }
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else { return }
        root.present(activityVC, animated: true)
        dismiss()
    }

    private func deleteAllDownloads() {
        let dm = DownloadManager.shared
        for song in playlist.songs {
            Task { await dm.delete(videoId: song.videoId) }
        }
    }
}
