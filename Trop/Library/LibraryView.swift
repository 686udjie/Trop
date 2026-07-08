//
//  LibraryView.swift
//  Trop
//
//  Created by 686udjie on 05/07/2026.
//

import SwiftUI

struct LibraryView: View {
    @State private var artists: [ArtistEntity] = []
    @State private var playlists: [PlaylistEntity] = []
    @State private var albums: [AlbumEntity] = []
    @State private var podcasts: [PodcastEntity] = []
    @State private var likedSongCount = 0
    @State private var isLoading = true
    @State private var selectedFilter: LibraryFilter? = nil

    private let gridColumns = [GridItem(.adaptive(minimum: 160), spacing: 16)]
    private var autoPlaylists: [AutoPlaylistInfo] {
        [
            AutoPlaylistInfo(id: "liked", title: "Liked Songs", icon: "heart.fill", subtitle: "\(likedSongCount) songs", route: .likedSongs),
            AutoPlaylistInfo(id: "top100", title: "My Top 100", icon: "trophy.fill", subtitle: "Top 100", route: .topSongs(limit: 100)),
        ]
    }

    enum LibraryFilter: String, CaseIterable {
        case playlists = "Playlists"
        case albums = "Albums"
        case artists = "Artists"
        case podcasts = "Podcasts"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    Text("Library")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                filterBar

                Group {
                    if isLoading {
                        Spacer()
                        ProgressView("Loading library...")
                        Spacer()
                    } else {
                        feedContent
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DetailRoute.self) { route in
                switch route {
                case .artist(let browseId):
                    ArtistDetailView(browseId: browseId)
                case .playlist(let playlistId):
                    PlaylistDetailView(playlistId: playlistId)
                case .album(let browseId):
                    AlbumDetailView(browseId: browseId)
                case .podcast(let browseId):
                    PodcastDetailView(browseId: browseId)
                case .autoPlaylist(let autoRoute):
                    PlaylistDetailView(autoPlaylistRoute: autoRoute)
                }
            }
            .task {
                await loadContent()
                Task {
                    await IncrementalSyncService.shared.forceFullSync()
                    await loadContent()
                }
            }
            .refreshable {
                await IncrementalSyncService.shared.forceFullSync()
                await loadContent()
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases, id: \.self) { filter in
                    Button(action: {
                        selectedFilter = selectedFilter == filter ? nil : filter
                    }) {
                        Text(filter.rawValue)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedFilter == filter
                                        ? Color.accentColor
                                        : Color(.systemGray5))
                            )
                            .foregroundColor(selectedFilter == filter
                                ? .white
                                : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Feed Content

    @ViewBuilder
    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                switch selectedFilter {
                case .playlists:
                    playlistsSection
                case .albums:
                    albumsSection
                case .artists:
                    artistsSection
                case .podcasts:
                    podcastsSection
                case nil:
                    playlistsSection
                    albumsSection
                    artistsSection
                    podcastsSection
                }
            }
        }
        .scrollIndicators(.automatic)
    }

    // MARK: - Playlists (Auto + User)

    private var playlistsSection: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(autoPlaylists) { info in
                NavigationLink(value: DetailRoute.autoPlaylist(info.route)) {
                    autoPlaylistCell(info: info)
                }
                .buttonStyle(.plain)
            }

            ForEach(playlists, id: \.id) { playlist in
                NavigationLink(value: DetailRoute.playlist(playlistId: playlist.id)) {
                        itemCell(
                            url: playlist.thumbnailUrl,
                            title: playlist.name,
                            subtitle: playlist.remoteSongCount.map { "\($0) songs" }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Artists

    private var artistsSection: some View {
        Group {
            if artists.isEmpty {
                emptyState("No subscribed artists yet")
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(artists, id: \.id) { artist in
                        NavigationLink(value: DetailRoute.artist(browseId: artist.id)) {
                            artistCell(
                                url: artist.thumbnailUrl,
                                name: artist.name
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Albums

    private var albumsSection: some View {
        Group {
            if albums.isEmpty {
                emptyState("No saved albums yet")
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(albums, id: \.id) { album in
                        NavigationLink(value: DetailRoute.album(browseId: album.id)) {
                            itemCell(
                                url: album.thumbnailUrl,
                                title: album.title,
                                subtitle: album.songCount > 0 ? "\(album.songCount) songs" : nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Podcasts

    private var podcastsSection: some View {
        Group {
            if podcasts.isEmpty {
                emptyState("No subscribed podcasts yet")
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(podcasts, id: \.id) { podcast in
                        NavigationLink(value: DetailRoute.podcast(browseId: podcast.id)) {
                            itemCell(
                                url: podcast.thumbnailUrl,
                                title: podcast.name,
                                subtitle: nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Components

    private func autoPlaylistCell(info: AutoPlaylistInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .aspectRatio(1, contentMode: .fill)
                Image(systemName: info.icon)
                    .font(.largeTitle)
                    .foregroundColor(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(info.title)
                .lineLimit(1)
                .font(.callout)
            if let subtitle = info.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func itemCell(url: String?, title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImageView(url: url)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(title).lineLimit(1).font(.callout)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func artistCell(url: String?, name: String) -> some View {
        VStack(spacing: 8) {
            AsyncImageView(url: url)
                .frame(width: 120, height: 120)
                .clipShape(Circle())
            Text(name).lineLimit(1).font(.callout)
        }
        .frame(maxWidth: .infinity)
    }

    private func emptyState(_ message: String) -> some View {
        ContentUnavailableView(
            message,
            systemImage: "music.note.list",
            description: Text("Your library will appear here after syncing")
        )
    }

    // MARK: - Data Loading

    private func loadContent() async {
        do {
            async let artistsFetch = DatabaseService.shared.fetchAll(ArtistEntity.self, sql: "SELECT * FROM artist ORDER BY name LIMIT 50")
            async let playlistsFetch = DatabaseService.shared.fetchAll(PlaylistEntity.self, sql: "SELECT * FROM playlist ORDER BY name LIMIT 50")
            async let albumsFetch = DatabaseService.shared.fetchAllAlbums()
            async let podcastsFetch = DatabaseService.shared.fetchAllPodcasts()
            async let countFetch = DatabaseService.shared.fetchAllLikedSongCount()
            artists = try await artistsFetch
            playlists = try await playlistsFetch
            albums = try await albumsFetch
            podcasts = try await podcastsFetch
            likedSongCount = try await countFetch
            isLoading = false
        } catch {
            print("[LibraryView] Failed to load: \(error)")
            isLoading = false
        }
    }
}

// MARK: - AutoPlaylist Info

struct AutoPlaylistInfo: Identifiable {
    let id: String
    let title: String
    let icon: String
    let subtitle: String?
    let route: AutoPlaylistRoute
}
