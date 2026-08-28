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
    @State private var settings = SettingsStore.shared
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    menuCard {
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
                            icon: "trash",
                            title: "Remove All Downloads",
                            subtitle: "Delete all offline tracks",
                            destructive: true
                        ) {
                            showClearConfirmation = true
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
        .alert("Remove All Downloads?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove All", role: .destructive) {
                Task {
                    await DownloadManager.shared.deleteAll()
                    dismiss()
                }
            }
        } message: {
            Text("This permanently deletes all offline tracks from your device.")
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

    private func addToQueue() {
        let np = NowPlaying.shared
        np.queueSongs.append(contentsOf: songs)
        np.persistQueueState()
    }
}
