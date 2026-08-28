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

    private var storageLabel: String {
        ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
    }

    var body: some View {
        List {
            Section {
                storageCard
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section {
                SettingsPickerRow("Download Quality", icon: "waveform", selection: $settings.downloadQuality)
                SettingsToggleRow("Wi-Fi Only", icon: "wifi", isOn: $settings.wifiOnlyDownloads)
                SettingsToggleRow("Auto-Download on Like", icon: "heart.fill", isOn: $settings.autoDownloadOnLike)
            } header: {
                Text("Preferences")
            } footer: {
                Text("Auto-download saves liked songs for offline playback. Wi-Fi Only blocks downloads on cellular data.")
            }
        }
        .navigationTitle("Download Settings")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .task { await refreshStats() }
        .onChange(of: downloadManager.downloads) { old, new in
            guard DownloadManager.shouldRefreshPersistedLibrary(old: old, new: new) else { return }
            Task { await refreshStats() }
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(storageLabel)
                        .font(.title2.weight(.bold))
                    Text("\(trackCount) offline \(trackCount == 1 ? "track" : "tracks")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func refreshStats() async {
        storageBytes = downloadManager.totalStorageBytes()
        trackCount = downloadManager.persistedDownloadCount
    }
}
