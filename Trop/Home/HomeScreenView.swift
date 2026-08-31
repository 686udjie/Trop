//
//  HomeScreenView.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import SwiftUI

struct HomeScreenView: View {
    @Environment(SettingsStore.self) private var settings
    @ObservedObject private var router = AppRouter.shared
    @State private var viewModel = HomeViewModel()
    @StateObject private var loginModel = LoginViewModel()

    @State private var pendingRoute: DetailRoute?
    @State private var speedDialEntries: [SpeedDialEntry] = []

    var body: some View {
        NavigationStack(path: $router.homePath) {
            VStack(spacing: 0) {
                TabHeaderView(
                    title: "Home",
                    accountIsLoggedIn: viewModel.isLoggedIn,
                    accountImageUrl: viewModel.accountImageUrl,
                    onHistory: { router.homePath.append(DetailRoute.history) },
                    onAccount: { viewModel.tapAccount() }
                )

                if viewModel.isLoading {
                    Spacer()
                    ShimmerLoadingView()
                    Spacer()
                } else if let error = viewModel.error {
                    errorView(error)
                } else {
                    homescreenContent
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar(.hidden, for: .navigationBar)
            .detailRouteDestinations()
            .onChange(of: pendingRoute) { _, route in
                if let route {
                    router.homePath.append(route)
                    pendingRoute = nil
                }
            }
            .sheet(isPresented: $viewModel.isLoginSheetPresented) {
                NavigationStack {
                    LoginWebView(model: loginModel)
                        .ignoresSafeArea()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { viewModel.isLoginSheetPresented = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $viewModel.isAccountSheetPresented) {
                accountSheet
            }
            .onChange(of: loginModel.isLoggedIn) { _, loggedIn in
                if loggedIn {
                    viewModel.isLoginSheetPresented = false
                    viewModel.handleLogin(
                        cookies: loginModel.cookies,
                        sapisid: loginModel.sapisid,
                        visitorData: loginModel.visitorData
                    )
                }
            }
            .onChange(of: viewModel.isLoginSheetPresented) { _, presented in
                if !presented {
                    loginModel.isPresented = false
                }
            }
            .task {
                await viewModel.restoreSession()
                viewModel.loadHomeData()
                await reloadSpeedDial()
                // Trigger library sync in background
                Task {
                    await IncrementalSyncService.shared.checkAndSyncIfStale()
                }
            }
            .task(id: viewModel.homeSections.count) {
                let urls = viewModel.homeSections
                    .flatMap(\.items)
                    .compactMap(\.thumbnailUrl)
                    .compactMap(URL.init)
                await ImagePreloader.shared.preload(urls)
            }
        }
    }

    private var homescreenContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let chips = viewModel.homePage?.chips, !chips.isEmpty {
                    ChipsRowView(
                        chips: chips,
                        selectedChip: viewModel.selectedChip,
                        onChipTap: { viewModel.toggleChip($0) }
                    )
                }

                ForEach(viewModel.homeSections.indices, id: \.self) { index in
                    let section = viewModel.homeSections[index]
                    sectionView(for: section)
                }

                GeometryReader { _ in
                    Color.clear
                        .onAppear {
                            let total = viewModel.homeSections.count
                            if total > 0 {
                                viewModel.loadMoreIfNeeded(
                                    currentIndex: total - 1,
                                    total: total
                                )
                            }
                        }
                }
                .frame(height: 1)
            }
        }
        .scrollIndicators(.automatic)
        .miniPlayerTracksScroll()
        .refreshable {
            await viewModel.refresh()
            await reloadSpeedDial()
            await IncrementalSyncService.shared.checkAndSyncIfStale()
        }
        .onChange(of: settings.hideExplicit) { _, _ in
            viewModel.syncSettings()
        }
        .onChange(of: settings.showQuickPicks) { _, _ in
            viewModel.syncSettings()
            Task { await viewModel.refresh() }
        }
        .onChange(of: settings.topListsLength) { _, _ in
            Task { await viewModel.refresh() }
        }
        .onChange(of: settings.contentCountry) { _, _ in
            Task { await viewModel.refresh() }
        }
    }

    private var accountSheet: some View {
        AccountSheetView(
            isLoggedIn: viewModel.isLoggedIn,
            titleText: viewModel.accountName,
            accountImageUrl: viewModel.accountImageUrl,
            onDone: { viewModel.isAccountSheetPresented = false },
            onLogin: {
                viewModel.isAccountSheetPresented = false
                DispatchQueue.main.async {
                    viewModel.isLoginSheetPresented = true
                }
            },
            onSettings: {
                viewModel.isAccountSheetPresented = false
                router.homePath.append(DetailRoute.settings)
            },
            onSignOut: { viewModel.logout() }
        )
    }

    private func refreshTask() async {
        while viewModel.isRefreshing {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    @ViewBuilder
    private func sectionView(for section: HomeSection) -> some View {
        switch section {
        case .quickPicks:
            quickPicksSection(section)
        case .keepListening:
            mixedSection(section)
        case .forgottenFavorites:
            songsSection(section)
        case .homePageSection(let sectionData, _):
            if sectionData.isSongsOnly {
                songsSection(section)
            } else {
                mixedSection(section)
            }
        default:
            mixedSection(section)
        }
    }

    @ViewBuilder
    private func quickPicksSection(_ section: HomeSection) -> some View {
        let pinnedSongs = speedDialEntries.map { $0.toSongItem() }
        let quickSongs = section.items.compactMap { if case .song(let s) = $0 { return s } else { return nil } }
        let combinedQueue = pinnedSongs + quickSongs

        if combinedQueue.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
            NavigationTitleView(title: section.displayTitle)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(60)), count: 4), spacing: 12) {
                    ForEach(speedDialEntries, id: \.videoId) { entry in
                        let song = entry.toSongItem()
                        YouTubeListItemView(
                            item: .song(song),
                            onTap: { handleSongTap(song, in: combinedQueue) },
                            onNavigate: { pendingRoute = $0 }
                        )
                        .frame(width: 280)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(settings.accentColor)
                                .padding(6)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                Task {
                                    try? await DatabaseService.shared.removeFromSpeedDial(videoId: entry.videoId)
                                    await reloadSpeedDial()
                                }
                            } label: {
                                Label("Unpin", systemImage: "pin.slash")
                            }
                        }
                    }

                    ForEach(section.items.indices, id: \.self) { i in
                        let item = section.items[i]
                        if case .song(let s) = item {
                            YouTubeListItemView(item: item, onTap: { handleSongTap(s, in: combinedQueue) }, onNavigate: { pendingRoute = $0 })
                                .frame(width: 280)
                        } else {
                            YouTubeListItemView(item: item, onTap: { handleItemTap(item) }, onNavigate: { pendingRoute = $0 })
                                .frame(width: 280)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            }
        }
    }

    private func songsSection(_ section: HomeSection) -> some View {
        let queue = section.items.compactMap { if case .song(let s) = $0 { return s } else { return nil } }
        return VStack(alignment: .leading, spacing: 8) {
            NavigationTitleView(title: section.displayTitle)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(60)), count: 4), spacing: 12) {
                    ForEach(section.items.indices, id: \.self) { i in
                        let item = section.items[i]
                        if case .song(let s) = item {
                            YouTubeListItemView(item: item, onTap: { handleSongTap(s, in: queue) }, onNavigate: { pendingRoute = $0 })
                                .frame(width: 280)
                        } else {
                            YouTubeListItemView(item: item, onTap: { handleItemTap(item) }, onNavigate: { pendingRoute = $0 })
                                .frame(width: 280)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func mixedSection(_ section: HomeSection) -> some View {
        let queue = section.items.compactMap { if case .song(let s) = $0 { return s } else { return nil } }
        return VStack(alignment: .leading, spacing: 8) {
            NavigationTitleView(title: section.displayTitle)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(section.items.indices, id: \.self) { i in
                        let item = section.items[i]
                        if case .song(let s) = item, !queue.isEmpty {
                            YouTubeGridItemView(item: item, onTap: { handleSongTap(s, in: queue) })
                        } else {
                            YouTubeGridItemView(item: item, onTap: { handleItemTap(item) })
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }.padding(.top, 8)
    }

    // MARK: - Quick Picks (pinned)

    private func reloadSpeedDial() async {
        speedDialEntries = (try? await DatabaseService.shared.fetchSpeedDial()) ?? []
    }

    private func handleSongTap(_ song: SongItem, in queue: [SongItem]) {
        Log.homeScreenView.debug("Tapped song in queue: \(song.title) queueCount=\(queue.count)")
        if let idx = queue.firstIndex(where: { $0.videoId == song.videoId }) {
            NowPlaying.shared.setQueue(queue, startIndex: idx)
        } else {
            NowPlaying.shared.setQueue([song], startIndex: 0)
        }
        playVideo(videoId: song.videoId)
    }

    private func handleItemTap(_ item: YTItem) {
        Log.homeScreenView.debug("Tapped item: \(item.title) type=\(typeName(item))")
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
                Log.homeScreenView.debug("Set radio queue with \(radio.songs.count) songs at index \(radio.currentIndex)")
            }
        case .episode(let e):
            playVideo(videoId: e.videoId)
        case .album(let a):
            Log.homeScreenView.debug("Navigating to album: \(a.browseId)")
            router.homePath.append(DetailRoute.album(browseId: a.browseId))
        case .artist(let a):
            Log.homeScreenView.debug("Navigating to artist: \(a.browseId)")
            router.homePath.append(DetailRoute.artist(browseId: a.browseId))
        case .playlist(let p):
            Log.homeScreenView.debug("Navigating to playlist: \(p.id)")
            router.homePath.append(DetailRoute.playlist(playlistId: p.id))
        case .podcast(let p):
            Log.homeScreenView.debug("Navigating to podcast: \(p.browseId)")
            router.homePath.append(DetailRoute.podcast(browseId: p.browseId))
        }
    }

    private func typeName(_ item: YTItem) -> String {
        switch item {
        case .song: return "song"
        case .album: return "album"
        case .artist: return "artist"
        case .playlist: return "playlist"
        case .podcast: return "podcast"
        case .episode: return "episode"
        }
    }

    private func playVideo(videoId: String) {
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: videoId)
                Log.homeScreenView.debug("Playing videoId=\(videoId)")
            } catch {
                Log.homeScreenView.error("Playback failed: \(error)")
            }
        }
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView(
            "Couldn't load your homescreen",
            systemImage: "wifi.slash",
            description: Text(error.localizedDescription)
        )
    }
}

#Preview {
    HomeScreenView()
}
