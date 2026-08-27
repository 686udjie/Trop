//
//  DownloadsView.swift
//  Trop
//

import SwiftUI

@MainActor
@Observable
final class DownloadsViewModel {
    var tracks: [DownloadedTrackEntity] = []
    var sort: DownloadManager.DownloadSort = .recent
    var isLoading = true
    var storageBytes: Int64 = 0

    private let downloadManager = DownloadManager.shared

    var songs: [SongItem] {
        tracks.map { SongItem(entity: $0) }
    }

    var activeDownloads: [(videoId: String, progress: Double)] {
        downloadManager.activeDownloads
    }

    var totalDuration: Int {
        tracks.reduce(0) { $0 + $1.duration }
    }

    func load() async {
        isLoading = true
        await refreshPersistedTracks()
        isLoading = false
    }

    func reloadSort(_ newSort: DownloadManager.DownloadSort) async {
        sort = newSort
        await refreshPersistedTracks()
    }

    func refreshPersistedTracks() async {
        tracks = await downloadManager.fetchAllSorted(by: sort)
        storageBytes = downloadManager.totalStorageBytes()
    }

    func delete(_ track: DownloadedTrackEntity) async {
        await downloadManager.delete(videoId: track.id)
        await refreshPersistedTracks()
        Log.downloadsView.debug("Removed download \(track.id)")
    }

    func deleteAll() async {
        await downloadManager.deleteAll()
        await refreshPersistedTracks()
    }
}

struct DownloadsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var viewModel = DownloadsViewModel()
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var showClearConfirmation = false
    @State private var pendingRoute: DetailRoute?

    private var storageLabel: String {
        ByteCountFormatter.string(fromByteCount: viewModel.storageBytes, countStyle: .file)
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.tracks.isEmpty && viewModel.activeDownloads.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .onChange(of: downloadManager.downloads) { old, new in
            guard DownloadManager.shouldRefreshPersistedLibrary(old: old, new: new) else { return }
            Task { await viewModel.refreshPersistedTracks() }
        }
        .alert("Remove All Downloads?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove All", role: .destructive) {
                Task { await viewModel.deleteAll() }
            }
        } message: {
            Text("This permanently deletes \(viewModel.tracks.count) downloaded track(s) from your device.")
        }
        .detailRouteSheet(item: $pendingRoute)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if !viewModel.tracks.isEmpty {
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Remove all downloads")
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink {
                DownloadSettingsView()
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Download settings")
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Loading downloads…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Downloads Yet", systemImage: "arrow.down.circle")
        } description: {
            Text("Save songs for offline listening from the player menu, or enable auto-download when you like a track.")
        } actions: {
            NavigationLink {
                DownloadSettingsView()
            } label: {
                Text("Download Settings")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(settings.accentColor)
        }
        .miniPlayerTracksScroll()
    }

    private var contentView: some View {
        List {
            Section {
                heroHeader
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            if !viewModel.activeDownloads.isEmpty {
                Section {
                    ForEach(viewModel.activeDownloads, id: \.videoId) { item in
                        ActiveDownloadRow(videoId: item.videoId, progress: item.progress)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    sectionHeader("Downloading", systemImage: "arrow.down.circle")
                }
            }

            if !viewModel.tracks.isEmpty {
                Section {
                    ForEach(viewModel.tracks, id: \.id) { track in
                        let song = SongItem(entity: track)
                        DownloadedSongRow(
                            song: song,
                            downloadedAt: track.downloadedAt,
                            onPlay: { playSong(song) },
                            onNavigate: { pendingRoute = $0 }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(track) }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader("Your Library", systemImage: "internaldrive")
                        sortBar
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .miniPlayerTracksScroll()
        .onChange(of: viewModel.sort) { _, newSort in
            Task { await viewModel.reloadSort(newSort) }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.leading, 4)
            .padding(.bottom, 4)
    }

    private var sortBar: some View {
        FilterChipBar(
            items: DownloadManager.DownloadSort.allCases,
            id: \.self,
            title: \.displayName,
            isSelected: { viewModel.sort == $0 },
            onTap: { sort in
                viewModel.sort = sort
            }
        )
        .padding(.horizontal, -16)
    }

    private var heroHeader: some View {
        VStack(spacing: 14) {
            artworkHero

            VStack(spacing: 6) {
                Text("Downloads")
                    .font(.title2.weight(.bold))

                Text(metadataLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !viewModel.songs.isEmpty {
                HStack(spacing: 20) {
                    Button(action: shufflePlay) {
                        Image(systemName: "shuffle")
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Shuffle")

                    Button(action: playAll) {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(settings.accentColor))
                            .shadow(color: settings.accentColor.opacity(0.4), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play all")
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var artworkHero: some View {
        let thumbnails = viewModel.tracks.prefix(4).compactMap(\.thumbnailUrl)
        if thumbnails.count >= 4 {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 2)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, url in
                    AsyncImageView(url: url)
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        } else if let url = thumbnails.first {
            AsyncImageView(url: url)
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
                .overlay(alignment: .bottomTrailing) {
                    offlineHeroBadge
                        .padding(10)
                }
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            settings.accentColor.opacity(0.9),
                            settings.accentColor.opacity(0.55),
                            Color.teal.opacity(0.65)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 200, height: 200)
                .overlay {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .symbolRenderingMode(.hierarchical)
                }
                .shadow(color: settings.accentColor.opacity(0.35), radius: 16, y: 6)
        }
    }

    private var offlineHeroBadge: some View {
        Label("Offline", systemImage: "arrow.down.circle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.ultraThinMaterial))
    }

    private var metadataLine: String {
        var parts: [String] = []
        let count = viewModel.tracks.count
        parts.append("\(count) \(count == 1 ? "song" : "songs")")
        if viewModel.totalDuration > 0 {
            parts.append(viewModel.totalDuration.formattedDuration)
        }
        if viewModel.storageBytes > 0 {
            parts.append(storageLabel)
        }
        return parts.joined(separator: " · ")
    }

    private func playAll() {
        let songs = viewModel.songs
        guard !songs.isEmpty else { return }
        NowPlaying.shared.setQueue(songs, startIndex: 0)
        Task { try? await PlaybackManager.shared.resolveAndPlay(videoId: songs[0].videoId) }
    }

    private func shufflePlay() {
        let songs = viewModel.songs.shuffled()
        guard !songs.isEmpty else { return }
        NowPlaying.shared.setQueue(songs, startIndex: 0)
        Task { try? await PlaybackManager.shared.resolveAndPlay(videoId: songs[0].videoId) }
    }

    private func playSong(_ song: SongItem) {
        let songs = viewModel.songs
        if let index = songs.firstIndex(where: { $0.videoId == song.videoId }) {
            NowPlaying.shared.setQueue(songs, startIndex: index)
        } else {
            NowPlaying.shared.setQueue([song], startIndex: 0)
        }
        Task { try? await PlaybackManager.shared.resolveAndPlay(videoId: song.videoId) }
    }
}

// MARK: - Rows

private struct ActiveDownloadRow: View {
    @Environment(SettingsStore.self) private var settings
    let videoId: String
    let progress: Double

    @State private var title = "Downloading…"
    @State private var artist = ""
    @State private var thumbnailUrl: String?

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumbnailUrl {
                        AsyncImageView(url: thumbnailUrl)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [settings.accentColor.opacity(0.5), settings.accentColor.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                Image(systemName: "music.note")
                                    .foregroundStyle(settings.accentColor.opacity(0.8))
                            }
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                downloadRing
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(artist.isEmpty ? "Preparing download…" : artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: progress)
                    .tint(settings.accentColor)
            }

            Spacer(minLength: 0)

            Text("\(Int(progress * 100))%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(settings.accentColor)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .task { await loadMetadata() }
    }

    private var downloadRing: some View {
        ZStack {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 22, height: 22)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(settings.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 18, height: 18)
            Image(systemName: "arrow.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(settings.accentColor)
        }
    }

    private func loadMetadata() async {
        if let entity = try? await DatabaseService.shared.fetchOne(SongEntity.self, key: videoId) {
            title = entity.title
            artist = entity.artistName ?? ""
            thumbnailUrl = entity.thumbnailUrl
            return
        }
        if let entity = try? await DatabaseService.shared.fetchOne(DownloadedTrackEntity.self, key: videoId) {
            title = entity.title
            artist = entity.artist
            thumbnailUrl = entity.thumbnailUrl
        }
    }
}

private struct DownloadedSongRow: View {
    @Environment(SettingsStore.self) private var settings
    let song: SongItem
    let downloadedAt: Date
    var onPlay: () -> Void
    var onNavigate: (DetailRoute) -> Void

    @State private var showSongMenu = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImageView(url: song.thumbnailUrl)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(2)
                    .background(Circle().fill(settings.accentColor))
                    .offset(x: 3, y: 3)
            }

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

            Button {
                showSongMenu = true
            } label: {
                Text("\u{22EE}")
                    .font(.body.weight(.black))
                    .foregroundStyle(settings.accentColor)
            }
            .sheet(isPresented: $showSongMenu) {
                SongMenuSheet(
                    song: song,
                    onNavigate: onNavigate
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .accessibilityHint("Saved \(downloadedAt.formatted(.relative(presentation: .named)))")
    }
}
