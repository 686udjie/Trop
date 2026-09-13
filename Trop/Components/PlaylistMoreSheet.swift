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
    @State private var showEditAlert = false
    @State private var editedName = ""

    var body: some View {
        SheetChrome {
            MenuCard {
                MenuRow(
                    icon: "pencil",
                    title: "Edit",
                    subtitle: "Edit playlist"
                ) {
                    editedName = playlist.title
                    showEditAlert = true
                }
                Divider()
                MenuRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Sync",
                    subtitle: "Sync this playlist with YouTube Music"
                ) {
                    onSync?()
                    dismiss()
                }
                Divider()
                MenuRow(
                    icon: "list.bullet",
                    title: "Add to Queue",
                    subtitle: "Add to the end of the queue"
                ) {
                    addToQueue()
                    dismiss()
                }
                Divider()
                MenuRow(
                    icon: "square.and.arrow.down",
                    title: "Download",
                    subtitle: "Download all songs for offline playback"
                ) {
                    downloadAll()
                    dismiss()
                }
                Divider()
                MenuRow(
                    icon: "square.and.arrow.up",
                    title: "Share",
                    subtitle: "Share this playlist with others"
                ) {
                    share()
                    dismiss()
                }
                Divider()
                MenuRow(
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
        .textPrompt(
            "Rename Playlist",
            isPresented: $showEditAlert,
            placeholder: "Playlist name",
            text: $editedName,
            okTitle: "Rename",
            onOK: renamePlaylist
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
        guard let url = URL.playlistShareURL(id: playlist.playlistId) else { return }
        presentShareSheet(items: [url])
        dismiss()
    }

    private func deleteAllDownloads() {
        let dm = DownloadManager.shared
        for song in playlist.songs {
            Task { await dm.delete(videoId: song.videoId) }
        }
    }
}
