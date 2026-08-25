//
//  LibraryView.swift
//  Trop
//
//  Created by 686udjie on 05/07/2026.
//

import SwiftUI
import GRDB

struct LibraryView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var artists: [ArtistEntity] = []
    @State private var playlists: [PlaylistEntity] = []
    @State private var albums: [AlbumEntity] = []
    @State private var podcasts: [PodcastEntity] = []
    @State private var likedSongCount = 0
    @State private var downloadedSongCount = 0
    @State private var isLoading = true
    @State private var selectedFilter: LibraryFilter?
    @State private var showCreateDialog = false
    @State private var playlistToDelete: PlaylistEntity?
    @State private var playlistSongCounts: [String: Int] = [:]

    @StateObject private var loginModel = LoginViewModel()
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var downloadManager = DownloadManager.shared

    @State private var accountName = "Guest"
    @State private var accountImageUrl: String?
    @State private var isLoginSheetPresented = false
    @State private var isAccountSheetPresented = false

    private let gridColumns = [GridItem(.adaptive(minimum: 160), spacing: 16)]
    private var autoPlaylists: [AutoPlaylistInfo] {
        [
            AutoPlaylistInfo(id: "liked", title: "Liked Songs", icon: "heart.fill", subtitle: "\(likedSongCount) songs", route: .likedSongs),
            AutoPlaylistInfo(id: "downloads", title: "Downloads", icon: "arrow.down.circle.fill", subtitle: downloadsSubtitle, route: nil, detailRoute: .downloads),
            AutoPlaylistInfo(id: "top100", title: "My Top 100", icon: "trophy.fill", subtitle: "Top 100", route: .topSongs(limit: 100))
        ]
    }

    private var downloadsSubtitle: String {
        downloadedSongCount == 0 ? "Offline" : "\(downloadedSongCount) songs"
    }

    enum LibraryFilter: String, CaseIterable {
        case playlists = "Playlists"
        case albums = "Albums"
        case artists = "Artists"
        case podcasts = "Podcasts"
    }

    var body: some View {
        NavigationStack(path: $router.libraryPath) {
            VStack(spacing: 0) {
                TabHeaderView(
                    title: "Library",
                    accountIsLoggedIn: loginModel.isLoggedIn,
                    accountImageUrl: accountImageUrl,
                    onHistory: { router.libraryPath.append(DetailRoute.history) },
                    onAccount: { tapAccount() }
                )

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
            .detailRouteDestinations()
            .overlay(alignment: .bottomTrailing) {
                                Button(action: { showCreateDialog = true }, label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(settings.accentColor))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                })
                .accessibilityLabel("Create playlist")
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
            .overlay {
                if showCreateDialog {
                    CreatePlaylistDialog(
                        isPresented: $showCreateDialog,
                        onCreated: { await loadContent() }
                    )
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showCreateDialog)
            .sheet(isPresented: $isLoginSheetPresented) {
                NavigationStack {
                    LoginWebView(model: loginModel)
                        .ignoresSafeArea()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { isLoginSheetPresented = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $isAccountSheetPresented) {
                accountSheet
            }
            .task {
                await loadContent()
                loginModel.restoreSessionIfPresent()
                await fetchAccountInfo()
                Task {
                    await IncrementalSyncService.shared.forceFullSync()
                    await loadContent()
                }
            }
            .onChange(of: loginModel.isLoggedIn) { _, loggedIn in
                if loggedIn {
                    isLoginSheetPresented = false
                    Task { await fetchAccountInfo() }
                }
            }
            .task(id: isLoading) {
                guard !isLoading else { return }
                let urls = (playlists.map(\.thumbnailUrl) + albums.map(\.thumbnailUrl) + artists.map(\.thumbnailUrl) + podcasts.map(\.thumbnailUrl))
                    .compactMap { $0 }
                    .compactMap(URL.init)
                await ImagePreloader.shared.preload(urls)
            }
            .refreshable {
                await IncrementalSyncService.shared.forceFullSync()
                await loadContent()
            }
            .onChange(of: downloadManager.downloads) { _, _ in
                Task {
                    downloadedSongCount = (await DownloadManager.shared.fetchAll()).count
                }
            }
            .alert("Delete Playlist", isPresented: .init(
                get: { playlistToDelete != nil },
                set: { if !$0 { playlistToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { playlistToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let p = playlistToDelete {
                        Task { await deletePlaylist(p) }
                    }
                }
            } message: {
                Text("Are you sure you want to delete \"\(playlistToDelete?.name ?? "")\"?")
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        FilterChipBar(
            items: LibraryFilter.allCases,
            id: \.self,
            title: \.rawValue,
            isSelected: { selectedFilter == $0 },
            onTap: { filter in
                selectedFilter = selectedFilter == filter ? nil : filter
            }
        )
    }

    // MARK: - Feed Content

    @ViewBuilder
    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                filterBar

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
        .miniPlayerTracksScroll()
    }

    // MARK: - Playlists (Auto + User)

    private var playlistsSection: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(autoPlaylists) { info in
                if let detailRoute = info.detailRoute {
                    NavigationLink(value: detailRoute) {
                        autoPlaylistCell(info: info)
                    }
                    .buttonStyle(.plain)
                } else if let route = info.route {
                    NavigationLink(value: DetailRoute.autoPlaylist(route)) {
                        autoPlaylistCell(info: info)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(playlists, id: \.id) { playlist in
                NavigationLink(value: DetailRoute.playlist(playlistId: playlist.id)) {
                    itemCell(
                        url: playlist.thumbnailUrl,
                        title: playlist.name,
                        subtitle: playlistSongCounts[playlist.id].map { "\($0) songs" }
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if playlist.isEditable {
                        Button(role: .destructive) {
                            playlistToDelete = playlist
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
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
                    .fill(autoPlaylistGradient(for: info.id))
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

    private func autoPlaylistGradient(for id: String) -> LinearGradient {
        switch id {
        case "downloads":
            return LinearGradient(
                colors: [settings.accentColor.opacity(0.9), Color.teal.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
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
            async let downloadsFetch = DownloadManager.shared.fetchAll()
            artists = try await artistsFetch
            playlists = try await playlistsFetch
            albums = try await albumsFetch
            podcasts = try await podcastsFetch
            likedSongCount = try await countFetch
            downloadedSongCount = (await downloadsFetch).count

            let rows: [(String, Int)] = try await DatabaseService.shared.read { db in
                try Row.fetchAll(db, sql: "SELECT playlist_id, COUNT(*) as cnt FROM playlist_song_map GROUP BY playlist_id")
                    .map { ($0["playlist_id"] as String, $0["cnt"] as Int) }
            }
            playlistSongCounts = Dictionary(uniqueKeysWithValues: rows)

            isLoading = false
        } catch {
            Log.libraryView.error("Failed to load: \(error)")
            isLoading = false
        }
    }

    private func deletePlaylist(_ playlist: PlaylistEntity) async {
        do {
            try await MutationService.shared.deletePlaylist(playlistId: playlist.id)
            await loadContent()
        } catch {
            Log.libraryView.error("Failed to delete playlist: \(error)")
        }
    }

    // MARK: - Account

    private func tapAccount() {
        isAccountSheetPresented = true
    }

    private func fetchAccountInfo() async {
        guard loginModel.isLoggedIn else { return }
        do {
            let info = try await InnerTube.shared.accountInfo()
            accountName = info.name
            accountImageUrl = info.thumbnailUrl
        } catch {
            Log.libraryView.error("Failed to fetch account info: \(error)")
        }
    }

    private var accountSheet: some View {
        AccountSheetView(
            isLoggedIn: loginModel.isLoggedIn,
            titleText: accountName,
            accountImageUrl: accountImageUrl,
            onDone: { isAccountSheetPresented = false },
            onLogin: {
                isAccountSheetPresented = false
                DispatchQueue.main.async {
                    isLoginSheetPresented = true
                }
            },
            onSettings: {
                isAccountSheetPresented = false
                router.libraryPath.append(DetailRoute.settings)
            },
            onSignOut: {
                loginModel.logout()
                accountName = "Guest"
                accountImageUrl = nil
                isAccountSheetPresented = false
            }
        )
    }
}

// MARK: - Create Playlist Dialog

struct CreatePlaylistDialog: View {
    @Environment(SettingsStore.self) private var settings
    @Binding var isPresented: Bool
    let onCreated: () async -> Void

    @State private var name = ""
    @State private var syncWithYouTube = false
    @State private var isCreating = false
    @State private var error: Error?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("New Playlist")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.top, 24)
                .padding(.bottom, 20)

            TextField("Playlist name", text: $name)
                .font(.body)
                .focused($isFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isFocused ? settings.accentColor : Color(.systemGray4), lineWidth: 1)
                )
                .autocorrectionDisabled()
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            // Sync toggle
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync playlist")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Syncs with your YouTube Music account. This cannot be changed later.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: $syncWithYouTube)
                    .labelsHidden()
                    .tint(settings.accentColor)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            if let error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(error.localizedDescription)
                        .font(.caption)
                }
                .foregroundColor(.red)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            Divider()
                .padding(.bottom, 4)

            HStack(spacing: 12) {
                                Button(action: { isPresented = false }, label: {
                    Text("Cancel")
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.systemGray6))
                        )
                })
                .buttonStyle(.plain)

                Button(action: {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    Task {
                        isCreating = true
                        do {
                            try await createPlaylist()
                            await onCreated()
                            isPresented = false
                        } catch {
                            self.error = error
                        }
                        isCreating = false
                    }
                }, label: {
                    HStack(spacing: 6) {
                        if isCreating {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        }
                        Text("Create")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(name.trimmingCharacters(in: .whitespaces).isEmpty ? settings.accentColor.opacity(0.4) : settings.accentColor)
                    )
                })
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 30, y: 10)
        .onTapGesture { }
        .onAppear { isFocused = true }
    }

    private func createPlaylist() async throws {
        let title = name.trimmingCharacters(in: .whitespaces)
        if syncWithYouTube {
            _ = try await MutationService.shared.createPlaylist(title: title)
        } else {
            let id = UUID().uuidString
            let entity = PlaylistEntity(
                id: id,
                browseId: nil,
                name: title,
                thumbnailUrl: nil,
                isEditable: true,
                bookmarkedAt: Date(),
                remoteSongCount: 0
            )
            try await DatabaseService.shared.insert(entity)
        }
    }
}

// MARK: - AutoPlaylist Info

struct AutoPlaylistInfo: Identifiable {
    let id: String
    let title: String
    let icon: String
    let subtitle: String?
    let route: AutoPlaylistRoute?
    var detailRoute: DetailRoute?
}
