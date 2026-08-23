//
//  SearchView.swift
//  Trop
//
//  Created by 686udjie on 03/07/2026.
//

import SwiftUI

struct SearchView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var viewModel = SearchViewModel()
    @ObservedObject private var router = AppRouter.shared

    @State private var pendingRoute: DetailRoute?
    @State private var hasFocusedOnce = false

    @StateObject private var loginModel = LoginViewModel()
    @State private var isLoginSheetPresented = false
    @State private var isAccountSheetPresented = false
    @State private var accountName = "Guest"
    @State private var accountImageUrl: String?

    var body: some View {
        NavigationStack(path: $router.searchPath) {
            VStack(spacing: 0) {
                TabHeaderView(
                    title: "Search",
                    accountIsLoggedIn: loginModel.isLoggedIn,
                    accountImageUrl: accountImageUrl,
                    onHistory: { router.searchPath.append(DetailRoute.history) },
                    onAccount: { tapAccount() }
                )

                content
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar(.hidden, for: .navigationBar)
            .searchable(
                text: $viewModel.fieldText,
                placement: .automatic,
                prompt: "Search"
            )
            .onSubmit(of: .search) { submit(nil) }
            .onChange(of: viewModel.fieldText) { _, _ in
                suppressNativeClearButtons()
            }
            .onChange(of: viewModel.phase) { _, _ in
                suppressNativeClearButtons()
            }
            .detailRouteDestinations()
            .onChange(of: pendingRoute) { _, route in
                if let route {
                    router.searchPath.append(route)
                    pendingRoute = nil
                }
            }
            .onAppear {
                suppressNativeClearButtons()
                viewModel.loadSearchHistory()
            }
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
            .onChange(of: loginModel.isLoggedIn) { _, loggedIn in
                if loggedIn {
                    isLoginSheetPresented = false
                    Task { await fetchAccountInfo() }
                }
            }
            .task {
                loginModel.restoreSessionIfPresent()
                await fetchAccountInfo()
            }
            .task(id: viewModel.results.count) {
                let urls = viewModel.results
                    .flatMap(\.items)
                    .compactMap(\.thumbnailUrl)
                    .compactMap(URL.init)
                await ImagePreloader.shared.preload(urls)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            if viewModel.searchHistory.isEmpty {
                noRecentSearchesView
            } else {
                searchHistoryView
            }
        case .typing:
            suggestionsAndLocalView
        case .loading:
            loadingView
        case .results:
            searchResultsList
        case .noResults:
            noResultsView
        case .failed:
            errorView(viewModel.error)
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ShimmerLoadingView()
            Spacer()
        }
    }

    // MARK: - Submission

    private func submit(_ text: String? = nil) {
        if let text {
            viewModel.fieldText = text
        }
        viewModel.submit()
    }

    // MARK: - Native clear button suppression

    @MainActor private func suppressNativeClearButtons() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for window in scenes.flatMap(\.windows) {
            Self.removeClearButton(from: window)
        }
    }

    @MainActor private static func removeClearButton(from view: UIView) {
        if let searchField = view as? UISearchTextField {
            searchField.clearButtonMode = .never
        }
        view.subviews.forEach(Self.removeClearButton(from:))
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
            Log.searchView.error("Failed to fetch account info: \(error)")
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
                router.searchPath.append(DetailRoute.settings)
            },
            onSignOut: {
                loginModel.logout()
                accountName = "Guest"
                accountImageUrl = nil
                isAccountSheetPresented = false
            }
        )
    }

    private var searchHistoryView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recently searched")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Button("Clear") {
                        viewModel.clearSearchHistory()
                    }
                    .font(.subheadline)
                    .foregroundColor(settings.accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                ForEach(viewModel.searchHistory, id: \.query) { entry in
                    Button {
                        submit(entry.query)
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .foregroundColor(settings.accentColor)
                            Text(entry.query)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.deleteSearchHistoryEntry(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
        .scrollIndicators(.automatic)
        .miniPlayerTracksScroll()
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private var suggestionsAndLocalView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !viewModel.localSongs.isEmpty || !viewModel.localArtists.isEmpty
                    || !viewModel.localAlbums.isEmpty || !viewModel.localPlaylists.isEmpty {
                    sectionLabel("In Library")

                    ForEach(viewModel.localSongs, id: \.id) { song in
                        let item = YTItem.song(SongItem(
                            videoId: song.id,
                            title: song.title,
                            artists: song.artistName.map { [YTArtist(name: cleanArtistDisplay($0))] } ?? [],
                            album: song.albumName,
                            duration: song.duration,
                            thumbnailUrl: song.thumbnailUrl,
                            isExplicit: false
                        ))
                        YouTubeListItemView(item: item, onTap: {
                            handleItemTap(item)
                        }, onNavigate: { pendingRoute = $0 })
                    }

                    ForEach(viewModel.localArtists, id: \.id) { artist in
                        let item = YTItem.artist(ArtistItem(
                            browseId: artist.id,
                            name: artist.name,
                            thumbnailUrl: artist.thumbnailUrl,
                            isSubscribed: false
                        ))
                        YouTubeListItemView(item: item, onTap: {
                            router.searchPath.append(DetailRoute.artist(browseId: artist.id))
                        }, onNavigate: { pendingRoute = $0 })
                    }

                    ForEach(viewModel.localAlbums, id: \.id) { album in
                        let item = YTItem.album(AlbumItem(
                            browseId: album.id,
                            title: album.title,
                            artists: [],
                            year: nil,
                            thumbnailUrl: album.thumbnailUrl,
                            playlistId: album.playlistId,
                            isExplicit: false
                        ))
                        YouTubeListItemView(item: item, onTap: {
                            router.searchPath.append(DetailRoute.album(browseId: album.id))
                        }, onNavigate: { pendingRoute = $0 })
                    }

                    ForEach(viewModel.localPlaylists, id: \.id) { playlist in
                        let item = YTItem.playlist(PlaylistItem(
                            id: playlist.browseId ?? playlist.id,
                            title: playlist.name,
                            author: nil,
                            thumbnailUrl: nil,
                            songCount: playlist.remoteSongCount
                        ))
                        YouTubeListItemView(item: item, onTap: {
                            router.searchPath.append(DetailRoute.playlist(playlistId: playlist.browseId ?? playlist.id))
                        }, onNavigate: { pendingRoute = $0 })
                    }
                }

                if !viewModel.suggestions.isEmpty {
                    sectionLabel("Suggestions")

                    ForEach(viewModel.suggestions, id: \.self) { suggestion in
                        Button {
                            submit(suggestion)
                        } label: {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                Text(suggestion)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .foregroundColor(.secondary)
                                    .font(.footnote)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .scrollIndicators(.automatic)
        .miniPlayerTracksScroll()
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !viewModel.availableFilters.isEmpty {
                    filterChips
                }

                ForEach(viewModel.filteredResults) { section in
                    NavigationTitleView(title: section.title)
                        .padding(.top, 8)

                    ForEach(section.items, id: \.id) { item in
                        YouTubeListItemView(item: item, onTap: {
                            handleItemTap(item)
                        }, onNavigate: { pendingRoute = $0 })
                    }
                }
            }
        }
        .scrollIndicators(.automatic)
        .miniPlayerTracksScroll()
    }

    /// Phase-change logging.
    private var phaseDescription: String {
        switch viewModel.phase {
        case .idle: return "idle"
        case .typing: return "typing(suggestions=\(viewModel.suggestions.count))"
        case .loading: return "loading"
        case .results: return "results(sections=\(viewModel.results.count), filters=\(viewModel.availableFilters.count))"
        case .noResults: return "noResults"
        case .failed: return "failed"
        }
    }

    private var filterChips: some View {
        FilterChipBar(
            items: viewModel.availableFilters,
            id: \.self,
            title: { $0 },
            isSelected: { filter in
                filter == "Library"
                    ? viewModel.isShowingLibrary
                    : viewModel.selectedSectionFilter == filter
            },
            onTap: { filter in
                if filter == "Library" {
                    let willShow = !viewModel.isShowingLibrary
                    viewModel.isShowingLibrary = willShow
                    viewModel.selectedSectionFilter = nil
                } else {
                    viewModel.selectedSectionFilter = filter
                    viewModel.isShowingLibrary = false
                }
            }
        )
    }

    private var noResultsView: some View {
        ContentUnavailableView(
            "No Results",
            systemImage: "magnifyingglass",
            description: Text("No results found for \"\(viewModel.submittedQuery)\"")
        )
    }

    private var noRecentSearchesView: some View {
        ContentUnavailableView(
            "No Recent Searches",
            systemImage: "magnifyingglass",
            description: Text("Your recent searches will appear here.")
        )
    }

    private func errorView(_ error: Error?) -> some View {
        ContentUnavailableView(
            "Search failed",
            systemImage: "exclamationmark.triangle",
            description: Text(error?.localizedDescription ?? "Something went wrong.")
        )
    }

    private func handleItemTap(_ item: YTItem) {
        switch item {
        case .song(let s):
            NowPlaying.shared.setQueue([s], startIndex: 0)
            playVideo(videoId: s.videoId)
            Task {
                guard let radio = try? await PersonalizationService.shared.fetchRadio(videoId: s.videoId),
                      radio.songs.count > 1 else { return }
                guard NowPlaying.shared.videoId == s.videoId else { return }
                NowPlaying.shared.queueSongs = radio.songs
                NowPlaying.shared.queueIndex = radio.currentIndex
            }
        case .episode(let e): playVideo(videoId: e.videoId)
        case .album(let a):   router.searchPath.append(DetailRoute.album(browseId: a.browseId))
        case .artist(let a):  router.searchPath.append(DetailRoute.artist(browseId: a.browseId))
        case .playlist(let p): router.searchPath.append(DetailRoute.playlist(playlistId: p.id))
        case .podcast(let p): router.searchPath.append(DetailRoute.podcast(browseId: p.browseId))
        }
    }

    private func playVideo(videoId: String) {
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: videoId)
            } catch {
                Log.searchView.error("Playback failed: \(error)")
            }
        }
    }
}
