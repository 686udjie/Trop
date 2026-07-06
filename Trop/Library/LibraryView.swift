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
    @State private var isLoading = true

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading library...")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if !playlists.isEmpty {
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(playlists, id: \.id) { playlist in
                                        NavigationLink(value: DetailRoute.playlist(playlistId: playlist.id)) {
                                            itemCell(
                                                url: playlist.thumbnailUrl.flatMap(URL.init),
                                                title: playlist.name,
                                                subtitle: playlist.remoteSongCount.map { "\($0) songs" }
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if !artists.isEmpty {
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(artists, id: \.id) { artist in
                                        NavigationLink(value: DetailRoute.artist(browseId: artist.id)) {
                                            artistCell(
                                                url: artist.thumbnailUrl.flatMap(URL.init),
                                                name: artist.name
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Library")
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

    private func itemCell(url: URL?, title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(1, contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3).aspectRatio(1, contentMode: .fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(title).lineLimit(1).font(.callout)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func artistCell(url: URL?, name: String) -> some View {
        VStack(spacing: 8) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            Text(name).lineLimit(1).font(.callout)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadContent() async {
        do {
            async let artistsFetch = DatabaseService.shared.fetchAll(ArtistEntity.self, sql: "SELECT * FROM artist ORDER BY name LIMIT 50")
            async let playlistsFetch = DatabaseService.shared.fetchAll(PlaylistEntity.self, sql: "SELECT * FROM playlist ORDER BY name LIMIT 50")
            artists = try await artistsFetch
            playlists = try await playlistsFetch
            isLoading = false
        } catch {
            print("[LibraryView] Failed to load: \(error)")
            isLoading = false
        }
    }
}
