//
//  DetailRoute.swift
//  Trop
//
//  Created by 686udjie on 03/07/2026.
//

import Foundation

/// Route destinations for detail view navigation.
/// Used with NavigationStack + NavigationPath to push album, artist, and playlist detail screens.
enum DetailRoute: Hashable {
    case album(browseId: String)
    case artist(browseId: String)
    case playlist(playlistId: String)
}
