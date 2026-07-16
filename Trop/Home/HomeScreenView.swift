//
//  HomeScreenView.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import SwiftUI

struct HomeScreenView: View {
    @State private var viewModel = HomeViewModel()
    @StateObject private var loginModel = LoginViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var pendingRoute: DetailRoute?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    Text("Home")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            navigationPath.append(DetailRoute.history)
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title3)
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        AccountButtonView(
                            isLoggedIn: viewModel.isLoggedIn,
                            accountImageUrl: viewModel.accountImageUrl,
                            onTap: { viewModel.tapAccount() }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

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
            .navigationDestination(for: DetailRoute.self) { route in
                switch route {
                case .album(let browseId):
                    AlbumDetailView(browseId: browseId)
                case .artist(let browseId):
                    ArtistDetailView(browseId: browseId)
                case .playlist(let playlistId):
                    PlaylistDetailView(playlistId: playlistId)
                case .podcast(let browseId):
                    PodcastDetailView(browseId: browseId)
                case .autoPlaylist(let autoRoute):
                    PlaylistDetailView(autoPlaylistRoute: autoRoute)
                case .history:
                    HistoryScreenView()
                }
            }
            .navigationDestination(item: $pendingRoute) { route in
                switch route {
                case .album(let browseId): AlbumDetailView(browseId: browseId)
                case .artist(let browseId): ArtistDetailView(browseId: browseId)
                case .playlist(let playlistId): PlaylistDetailView(playlistId: playlistId)
                case .podcast(let browseId): PodcastDetailView(browseId: browseId)
                case .autoPlaylist(let autoRoute): PlaylistDetailView(autoPlaylistRoute: autoRoute)
                case .history: HistoryScreenView()
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
        .refreshable {
            viewModel.refresh()
            await refreshTask()
            await IncrementalSyncService.shared.checkAndSyncIfStale()
        }
    }

    private var accountSheet: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AccountButtonView(
                            isLoggedIn: viewModel.isLoggedIn,
                            accountImageUrl: viewModel.accountImageUrl,
                            onTap: {}
                        )
                        .scaleEffect(1.3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.accountName)
                                .font(.headline)
                            if viewModel.isLoggedIn {
                                Text("Signed in")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Not signed in")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if viewModel.isLoggedIn {
                    Section {
                        Button(role: .destructive) {
                            viewModel.logout()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { viewModel.isAccountSheetPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
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

    private func quickPicksSection(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationTitleView(title: section.displayTitle)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(60)), count: 4), spacing: 12) {
                    ForEach(section.items.indices, id: \.self) { i in
                        let item = section.items[i]
                        YouTubeListItemView(item: item, onTap: { handleItemTap(item) }, onNavigate: { pendingRoute = $0 })
                            .frame(width: 280)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func songsSection(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationTitleView(title: section.displayTitle)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(60)), count: 4), spacing: 12) {
                    ForEach(section.items.indices, id: \.self) { i in
                        let item = section.items[i]
                        YouTubeListItemView(item: item, onTap: { handleItemTap(item) }, onNavigate: { pendingRoute = $0 })
                            .frame(width: 280)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func mixedSection(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationTitleView(title: section.displayTitle)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(section.items.indices, id: \.self) { i in
                        let item = section.items[i]
                        YouTubeGridItemView(item: item, onTap: { handleItemTap(item) })
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 8)
    }

    private func handleItemTap(_ item: YTItem) {
        print("[HomeScreenView] Tapped item: \(item.title) type=\(typeName(item))")
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
                print("[HomeScreenView] Set radio queue with \(radio.songs.count) songs at index \(radio.currentIndex)")
            }
        case .episode(let e):
            playVideo(videoId: e.videoId)
        case .album(let a):
            print("[HomeScreenView] Navigating to album: \(a.browseId)")
            navigationPath.append(DetailRoute.album(browseId: a.browseId))
        case .artist(let a):
            print("[HomeScreenView] Navigating to artist: \(a.browseId)")
            navigationPath.append(DetailRoute.artist(browseId: a.browseId))
        case .playlist(let p):
            print("[HomeScreenView] Navigating to playlist: \(p.id)")
            navigationPath.append(DetailRoute.playlist(playlistId: p.id))
        case .podcast(let p):
            print("[HomeScreenView] Navigating to podcast: \(p.browseId)")
            navigationPath.append(DetailRoute.podcast(browseId: p.browseId))
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
                print("[HomeScreenView] Playing videoId=\(videoId)")
            } catch {
                print("[HomeScreenView] Playback failed: \(error)")
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
