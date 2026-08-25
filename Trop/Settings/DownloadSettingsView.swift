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
                storageCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
        .navigationTitle("Download Settings")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .task { await refreshStats() }
        .onChange(of: downloadManager.downloads) { old, new in
            guard DownloadManager.shouldRefreshPersistedLibrary(old: old, new: new) else { return }
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

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [settings.accentColor.opacity(0.85), settings.accentColor.opacity(0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    Image(systemName: "internaldrive.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(storageLabel)
                        .font(.title2.weight(.bold))
                    Text("\(trackCount) offline \(trackCount == 1 ? "track" : "tracks")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if trackCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(settings.accentColor)
                    Text("Stored on this device for offline playback")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundStyle(.secondary)
                    Text("Download songs from the player menu to fill your offline library")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
