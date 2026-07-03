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
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    Spacer()
                    ShimmerLoadingView()
                    Spacer()
                } else if let error = viewModel.error {
                    errorView(error)
                } else if viewModel.isFocused == true || (viewModel.searchSections.isEmpty && !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    suggestionsAndLocalView
                } else if !viewModel.searchSections.isEmpty {
                    searchResultsView
                } else {
                    initialPromptView
                }
            }
            .navigationTitle("Search")
            .customSearchable(
                text: $viewModel.searchText,
                focused: $viewModel.isFocused,
                onSubmit: {
                    viewModel.performSearch()
                },
                onCancel: {
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
                }
            }
        }
    }
    
    private var suggestionsAndLocalView: some View {
        List {
            // Local results section
            if !viewModel.localSongs.isEmpty || !viewModel.localArtists.isEmpty || !viewModel.localAlbums.isEmpty || !viewModel.localPlaylists.isEmpty {
                Section(header: Text("In Library").textCase(.uppercase)) {
                    ForEach(viewModel.localSongs, id: \.id) { song in
                        let item = YTItem.song(SongItem(
                            videoId: song.id,
                            title: song.title,
                            artists: song.artistName.map { [YTArtist(name: $0)] } ?? [],
                            album: song.albumName,
                            duration: song.duration,
                            thumbnailUrl: song.thumbnailUrl,
                            isExplicit: false
                        ))
                        YouTubeListItemView(item: item, onTap: {
                            playVideo(videoId: song.id)
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
            
            // Autocomplete suggestions section
            if !viewModel.suggestions.isEmpty {
                Section(header: Text("Suggestions").textCase(.uppercase)) {
                    ForEach(viewModel.suggestions, id: \.self) { suggestion in
                        Button(action: {
                            viewModel.searchText = suggestion
                            viewModel.performSearch()
                        }) {
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
    
    private var searchResultsView: some View {
        List {
            ForEach(viewModel.searchSections) { section in
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
    
    private var initialPromptView: some View {
        ContentUnavailableView(
            "Search YouTube Music",
            systemImage: "magnifyingglass",
            description: Text("Find songs, albums, artists, and playlists")
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
        case .song(let s):    playVideo(videoId: s.videoId)
        case .episode(let e): playVideo(videoId: e.videoId)
        case .album(let a):   navigationPath.append(DetailRoute.album(browseId: a.browseId))
        case .artist(let a):  navigationPath.append(DetailRoute.artist(browseId: a.browseId))
        case .playlist(let p): navigationPath.append(DetailRoute.playlist(playlistId: p.id))
        case .podcast: break
        }
    }
    
    private func playVideo(videoId: String) {
        Task {
            try? await PlaybackManager.shared.resolveAndPlay(videoId: videoId)
        }
    }
}
