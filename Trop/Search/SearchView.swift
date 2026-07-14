//
//  SearchView.swift
//  Trop
//
//  Created by 686udjie on 03/07/2026.
//

import SwiftUI

struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    @State private var navigationPath = NavigationPath()
    var onExitSearch: (() -> Void)?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    Spacer()
                    ShimmerLoadingView()
                    Spacer()
                } else if let error = viewModel.error {
                    errorView(error)
                } else if !viewModel.searchSections.isEmpty {
                    if !viewModel.availableFilters.isEmpty {
                        filterChips
                    }
                    searchResultsList
                } else if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    suggestionsAndLocalView
                } else if !viewModel.searchHistory.isEmpty {
                    searchHistoryView
                } else {
                    noRecentSearchesView
                }
            }
            .navigationTitle("Search")
            .customSearchable(
                text: $viewModel.searchText,
                focused: $viewModel.isFocused,
                hideCancelButton: false,
                hideClearButton: true,
                onSubmit: {
                    viewModel.performSearch()
                },
                onCancel: {
                    onExitSearch?()
                    viewModel.clearSearch()
                }
            )
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.onSearchTextChange()
            }
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
            .onAppear {
                if navigationPath.isEmpty {
                    viewModel.isFocused = true
                }
                viewModel.loadSearchHistory()
            }
        }
    }

    private var searchHistoryView: some View {
        List {
            Section {
                ForEach(viewModel.searchHistory, id: \.query) { entry in
                    Button {
                        viewModel.searchText = entry.query
                        viewModel.performSearch()
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .foregroundColor(.blue)
                            Text(entry.query)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteSearchHistoryEntry(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Recently searched")
                        .textCase(nil)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Button("Clear") {
                        viewModel.clearSearchHistory()
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
            }
        }
        .listStyle(.plain)
    }

    private var suggestionsAndLocalView: some View {
        List {
            if !viewModel.localSongs.isEmpty || !viewModel.localArtists.isEmpty
                || !viewModel.localAlbums.isEmpty || !viewModel.localPlaylists.isEmpty {
                Section(header: Text("In Library").textCase(.uppercase)) {
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
                            guard case .song(let s) = item else { return }
                            NowPlaying.shared.setQueue([s], startIndex: 0)
                            playVideo(videoId: song.id)
                            Task {
                                guard let radio = try? await PersonalizationService.shared.fetchRadio(videoId: s.videoId),
                                      radio.songs.count > 1 else { return }
                                guard NowPlaying.shared.videoId == s.videoId else { return }
                                NowPlaying.shared.queueSongs = radio.songs
                                NowPlaying.shared.queueIndex = radio.currentIndex
                            }
                        })
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 4)
                    }

                    ForEach(viewModel.localArtists, id: \.id) { artist in
                        let item = YTItem.artist(ArtistItem(
                            browseId: artist.id,
                            name: artist.name,
                            thumbnailUrl: artist.thumbnailUrl,
                            isSubscribed: false
                        ))
                        YouTubeListItemView(item: item, onTap: {
                            navigationPath.append(DetailRoute.artist(browseId: artist.id))
                        })
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 4)
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
                            navigationPath.append(DetailRoute.album(browseId: album.id))
                        })
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 4)
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
                            navigationPath.append(DetailRoute.playlist(playlistId: playlist.browseId ?? playlist.id))
                        })
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 4)
                    }
                }
            }

            if !viewModel.suggestions.isEmpty {
                Section(header: Text("Suggestions").textCase(.uppercase)) {
                    ForEach(viewModel.suggestions, id: \.self) { suggestion in
                        Button {
                            viewModel.searchText = suggestion
                            viewModel.performSearch()
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
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var searchResultsList: some View {
        List {
            ForEach(viewModel.filteredSections) { section in
                Section(header: Text(section.title).font(.headline).foregroundColor(.primary).textCase(nil)) {
                    ForEach(section.items, id: \.id) { item in
                        YouTubeListItemView(item: item, onTap: {
                            handleItemTap(item)
                        })
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.availableFilters, id: \.self) { filter in
                    Button {
                        if filter == "Library" {
                            let willShow = !viewModel.isShowingLibrary
                            viewModel.isShowingLibrary = willShow
                            viewModel.selectedSectionFilter = nil
                        } else {
                            viewModel.selectedSectionFilter = filter
                            viewModel.isShowingLibrary = false
                        }
                    } label: {
                        let isSelected = filter == "Library"
                            ? viewModel.isShowingLibrary
                            : viewModel.selectedSectionFilter == filter
                        Text(filter)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isSelected
                                        ? Color.accentColor
                                        : Color(.systemGray5))
                            )
                            .foregroundColor(isSelected
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

    private var noRecentSearchesView: some View {
        ContentUnavailableView(
            "No Recent Searches",
            systemImage: "magnifyingglass",
            description: Text("Your recent searches will appear here.")
        )
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView(
            "Search failed",
            systemImage: "exclamationmark.triangle",
            description: Text(error.localizedDescription)
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
        case .album(let a):   navigationPath.append(DetailRoute.album(browseId: a.browseId))
        case .artist(let a):  navigationPath.append(DetailRoute.artist(browseId: a.browseId))
        case .playlist(let p): navigationPath.append(DetailRoute.playlist(playlistId: p.id))
        case .podcast(let p): navigationPath.append(DetailRoute.podcast(browseId: p.browseId))
        }
    }

    private func playVideo(videoId: String) {
        Task {
            do {
                try await PlaybackManager.shared.resolveAndPlay(videoId: videoId)
            } catch {
                print("[SearchView] Playback failed: \(error)")
            }
        }
    }
}
