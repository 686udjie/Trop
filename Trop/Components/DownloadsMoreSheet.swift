//
//  DownloadsMoreSheet.swift
//  Trop
//
//  Created by 686udjie on 28/08/2026.
//

import SwiftUI

struct DownloadsMoreSheet: View {
    let songs: [SongItem]

    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirmation = false

    var body: some View {
        SheetChrome {
            MenuCard {
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
                    icon: "trash",
                    title: "Remove All Downloads",
                    subtitle: "Delete all offline tracks",
                    destructive: true
                ) {
                    showClearConfirmation = true
                }
            }
        }
        .destructiveConfirm(
            "Remove All Downloads?",
            isPresented: $showClearConfirmation,
            message: Text("This permanently deletes all offline tracks from your device."),
            confirmTitle: "Remove All"
        ) {
            Task {
                await DownloadManager.shared.deleteAll()
                dismiss()
            }
        }
    }

    // MARK: - Actions

    private func addToQueue() {
        let np = NowPlaying.shared
        np.queueSongs.append(contentsOf: songs)
        np.persistQueueState()
    }
}
