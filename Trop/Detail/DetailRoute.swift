//
//  DetailRoute.swift
//  Trop
//
//  Created by 686udjie on 03/07/2026.
//

import Foundation

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
        }
    }

    case album(browseId: String)
    case artist(browseId: String)
    case playlist(playlistId: String)
    case podcast(browseId: String)
    case autoPlaylist(AutoPlaylistRoute)
    case history
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
