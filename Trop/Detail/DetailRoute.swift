//
//  DetailRoute.swift
//  Trop
//
//  Created by 686udjie on 03/07/2026.
//

import Foundation
import SwiftUI

/// Route destinations for detail view navigation.
/// Used with NavigationStack + NavigationPath to push detail screens.
enum DetailRoute: Hashable, Identifiable {
    var id: String {
        switch self {
        case .album(let browseId): return "album_\(browseId)"
        case .artist(let browseId): return "artist_\(browseId)"
        case .playlist(let playlistId): return "playlist_\(playlistId)"
        case .podcast(let browseId): return "podcast_\(browseId)"
        case .autoPlaylist(let route): return "autoPlaylist_\(String(describing: route))"
        case .history: return "history"
        case .settings: return "settings"
        }
    }

    case album(browseId: String)
    case artist(browseId: String)
    case playlist(playlistId: String)
    case podcast(browseId: String)
    case autoPlaylist(AutoPlaylistRoute)
    case history
    case settings
}

/// Shared view resolving a `DetailRoute` to its target destination view.
struct DetailRouteDestinationView: View {
    let route: DetailRoute

    var body: some View {
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
        case .settings:
            SettingsView()
        }
    }
}

extension View {
    /// Registers standard DetailRoute navigation 
    func detailRouteDestinations() -> some View {
        self.navigationDestination(for: DetailRoute.self) { route in
            DetailRouteDestinationView(route: route)
        }
    }

    /// Presents a DetailRoute destination in a NavigationStack
    func detailRouteSheet(item: Binding<DetailRoute?>) -> some View {
        self.sheet(item: item) { route in
            NavigationStack {
                DetailRouteDestinationView(route: route)
            }
        }
    }
}

enum AutoPlaylistRoute: Hashable {
    case likedSongs
    case topSongs(limit: Int)
}

enum TopPeriod: String, CaseIterable, Hashable {
    case allTime = "All Time"
    case year = "Past Year"
    case month = "Past Month"
    case week = "Past Week"
    case day = "Past 24 Hours"

    var dateFrom: Date {
        let now = Date()
        switch self {
        case .allTime: return Date.distantPast
        case .year: return Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        case .month: return Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        case .week: return Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        case .day: return Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        }
    }
}
