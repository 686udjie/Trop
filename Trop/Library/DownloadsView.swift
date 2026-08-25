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

    func load() async {
        isLoading = true
        tracks = await downloadManager.fetchAllSorted(by: sort)
        storageBytes = downloadManager.totalStorageBytes()
        isLoading = false
    }

    func reloadSort(_ newSort: DownloadManager.DownloadSort) async {
        sort = newSort
        await load()
    }

    func delete(_ track: DownloadedTrackEntity) async {
        await downloadManager.delete(videoId: track.id)
        await load()
    }

    func deleteAll() async {
        await downloadManager.deleteAll()
        await load()
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
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .onChange(of: downloadManager.downloads) { _, _ in
            Task { await viewModel.load() }
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
            Menu {
                Picker("Sort", selection: $viewModel.sort) {
                    ForEach(DownloadManager.DownloadSort.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                if !viewModel.tracks.isEmpty {
                    Divider()
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Remove All", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
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
            Text("Save songs for offline listening from the player menu or by liking tracks with auto-download enabled.")
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
        VStack(spacing: 0) {
            header
                .padding(.bottom, 8)

            if !viewModel.activeDownloads.isEmpty {
                activeDownloadsSection
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }

            if !viewModel.tracks.isEmpty {
                songList
            }
        }
        .miniPlayerTracksScroll()
        .onChange(of: viewModel.sort) { _, newSort in
            Task { await viewModel.reloadSort(newSort) }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                settings.accentColor.opacity(0.85),
                                settings.accentColor.opacity(0.45),
                                Color.purple.opacity(0.55)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 200)
                    .shadow(color: settings.accentColor.opacity(0.35), radius: 18, y: 8)

                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 52, weight: .medium))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)

                    Text("\(viewModel.tracks.count)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(viewModel.tracks.count == 1 ? "song" : "songs")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            VStack(spacing: 4) {
                Text("Offline Library")
                    .font(.title2.weight(.bold))
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                        .font(.caption.weight(.semibold))
                    Text(storageLabel)
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }

            if !viewModel.songs.isEmpty {
                HStack(spacing: 20) {
                    Button(action: shufflePlay) {
                        Image(systemName: "shuffle")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color(.systemGray6)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Shuffle")

                    Button(action: playAll) {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(settings.accentColor))
                            .shadow(color: settings.accentColor.opacity(0.35), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play all")
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 16)
    }

    private var activeDownloadsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Downloading", systemImage: "arrow.down.circle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(viewModel.activeDownloads, id: \.videoId) { item in
                    ActiveDownloadRow(videoId: item.videoId, progress: item.progress)
                    if item.videoId != viewModel.activeDownloads.last?.videoId {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private var songList: some View {
        List {
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
        }
        .listStyle(.plain)
        .scrollDisabled(false)
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

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 3)
                    .frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(settings.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 36, height: 36)
                Image(systemName: "arrow.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(settings.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(artist.isEmpty ? "Fetching stream…" : artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: progress)
                    .tint(settings.accentColor)
            }

            Spacer(minLength: 0)

            Text("\(Int(progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .task { await loadMetadata() }
    }

    private func loadMetadata() async {
        if let entity = try? await DatabaseService.shared.fetchOne(SongEntity.self, key: videoId) {
            title = entity.title
            artist = entity.artistName ?? ""
            return
        }
        if let entity = try? await DatabaseService.shared.fetchOne(DownloadedTrackEntity.self, key: videoId) {
            title = entity.title
            artist = entity.artist
        }
    }
}

private struct DownloadedSongRow: View {
    @Environment(SettingsStore.self) private var settings
    let song: SongItem
    let downloadedAt: Date
    var onPlay: () -> Void
    var onNavigate: (DetailRoute) -> Void

    private var downloadedLabel: String {
        downloadedAt.formatted(.relative(presentation: .named))
    }

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImageView(url: song.thumbnailUrl)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(settings.accentColor))
                        .offset(x: 4, y: 4)
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

                    Text("Saved \(downloadedLabel)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                SongMenuView(
                    songItem: song,
                    webUrl: song.webUrl,
                    artistBrowseId: song.firstArtistBrowseId,
                    albumBrowseId: song.firstAlbumBrowseId,
                    onNavigate: onNavigate
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
