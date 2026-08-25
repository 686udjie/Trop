//
//  DownloadSettingsView.swift
//  Trop
//

import SwiftUI

struct DownloadSettingsView: View {
    @State private var settings = SettingsStore.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var storageBytes: Int64 = 0
    @State private var trackCount = 0
    @State private var showClearConfirmation = false

    private var storageLabel: String {
        ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [settings.accentColor.opacity(0.8), settings.accentColor.opacity(0.45)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: "internaldrive.fill")
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(storageLabel)
                            .font(.headline)
                        Text("\(trackCount) downloaded \(trackCount == 1 ? "track" : "tracks")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Storage")
            }

            Section {
                SettingsPickerRow("Download Quality", icon: "waveform", selection: $settings.downloadQuality)
                SettingsToggleRow("Wi-Fi Only", icon: "wifi", isOn: $settings.wifiOnlyDownloads)
                SettingsToggleRow("Auto-Download on Like", icon: "heart.fill", isOn: $settings.autoDownloadOnLike)
            } header: {
                Text("Downloads")
            } footer: {
                Text("Auto-download saves liked songs for offline playback. Wi-Fi Only pauses downloads on cellular data.")
            }

            if trackCount > 0 {
                Section {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Remove All Downloads", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .task { await refreshStats() }
        .onChange(of: downloadManager.downloads) { _, _ in
            Task { await refreshStats() }
        }
        .alert("Remove All Downloads?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove All", role: .destructive) {
                Task {
                    await downloadManager.deleteAll()
                    await refreshStats()
                }
            }
        } message: {
            Text("This permanently deletes all offline tracks from your device.")
        }
    }

    private func refreshStats() async {
        storageBytes = downloadManager.totalStorageBytes()
        trackCount = await downloadManager.fetchAll().count
    }
}
