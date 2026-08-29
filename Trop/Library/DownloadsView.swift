//
//  DownloadsView.swift
//  Trop
//

import SwiftUI

struct DownloadsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var viewModel = DownloadsViewModel()
    @Environment(\.downloadManager) private var downloadManager
    @State private var pendingRoute: DetailRoute?
    @State private var showMoreSheet = false

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
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .onChange(of: downloadManager.downloads) { old, new in
            guard DownloadManager.shouldRefreshPersistedLibrary(old: old, new: new) else { return }
            Task { await viewModel.refreshTracks() }
        }
        .detailRouteSheet(item: $pendingRoute)
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
        ScrollView {
            LazyVStack(spacing: 0) {
                header
                    .padding(.bottom, 8)

                if !viewModel.activeDownloads.isEmpty {
                    activeDownloadsSection
                }

                if !viewModel.tracks.isEmpty {
                    songList
                }
            }
        }
        .scrollDisabled(viewModel.isLoading)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .miniPlayerTracksScroll()
    }

    private var header: some View {
        PlaylistHeaderView(
            title: "Downloads",
            thumbnails: viewModel.thumbnailUrls,
            songCount: viewModel.tracks.count,
            duration: viewModel.totalDuration,
            accentColor: settings.accentColor,
            onPlay: playAll,
            onShuffle: shufflePlay,
            onMore: { showMoreSheet = true }
        )
        .sheet(isPresented: $showMoreSheet) {
            DownloadsMoreSheet(songs: viewModel.songs)
        }
    }

    private var activeDownloadsSection: some View {
        VStack(spacing: 0) {
            SectionLabel(title: "Downloading", systemImage: "arrow.down.circle")
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            ForEach(viewModel.activeDownloads, id: \.videoId) { item in
                ActiveDownloadRow(videoId: item.videoId, progress: item.progress)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
        }
        .padding(.bottom, 16)
    }

    private var songList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.songs.enumerated()), id: \.offset) { index, song in
                DownloadedSongRow(
                    song: song,
                    onPlay: { playSong(song) },
                    onNavigate: { pendingRoute = $0 }
                )

                if index < viewModel.songs.count - 1 {
                    Divider()
                        .padding(.leading, 76)
                }
            }
        }
    }

    private func playAll() {
        let songs = viewModel.songs
        guard !songs.isEmpty else { return }
        let first = songs[0]
        NowPlaying.shared.setQueue(songs, startIndex: 0)
        let displayArtist = first.artists.map(\.name).joined(separator: ", ")
        NowPlaying.shared.update(
            title: first.title, artist: displayArtist, videoId: first.videoId,
            album: first.album, artists: first.artists
        )
        Task { await playLocal(first) }
    }

    private func shufflePlay() {
        let songs = viewModel.songs.shuffled()
        guard !songs.isEmpty else { return }
        let first = songs[0]
        NowPlaying.shared.setQueue(songs, startIndex: 0)
        let displayArtist = first.artists.map(\.name).joined(separator: ", ")
        NowPlaying.shared.update(
            title: first.title, artist: displayArtist, videoId: first.videoId,
            album: first.album, artists: first.artists
        )
        Task { await playLocal(first) }
    }

    private func playSong(_ song: SongItem) {
        let songs = viewModel.songs
        if let index = songs.firstIndex(where: { $0.videoId == song.videoId }) {
            NowPlaying.shared.setQueue(songs, startIndex: index)
        } else {
            NowPlaying.shared.setQueue([song], startIndex: 0)
        }
        let displayArtist = song.artists.map(\.name).joined(separator: ", ")
        NowPlaying.shared.update(
            title: song.title, artist: displayArtist, videoId: song.videoId,
            album: song.album, artists: song.artists
        )
        Task { await playLocal(song) }
    }

    private func playLocal(_ song: SongItem) async {
        guard let localURL = await DownloadManager.shared.localURL(for: song.videoId) else { return }
        let artists = song.artists
        let displayArtist = artists.map(\.name).joined(separator: ", ")
        await PlayerController.shared.play(
            url: localURL.absoluteString,
            title: song.title,
            artist: displayArtist,
            videoId: song.videoId,
            duration: TimeInterval(song.duration),
            artists: artists
        )
        await MainActor.run {
            NowPlaying.shared.updateVideoAvailability(hasVideoContent: false)
        }
    }
}

@MainActor
@Observable
final class DownloadsViewModel {
    var tracks: [DownloadedTrackEntity] = []
    var isLoading = true

    private let downloadManager = DownloadManager.shared

    var songs: [SongItem] { tracks.map { SongItem(entity: $0) } }
    var activeDownloads: [(videoId: String, progress: Double)] { downloadManager.activeDownloads }
    var totalDuration: Int { tracks.reduce(0) { $0 + $1.duration } }
    var thumbnailUrls: [String] { tracks.prefix(4).compactMap(\.thumbnailUrl) }

    func load() async {
        isLoading = true
        await refreshTracks()
        isLoading = false
    }

    func refreshTracks() async {
        tracks = await downloadManager.fetchAllSorted(by: .recent)
    }
}
