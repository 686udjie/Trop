//
//  HomePage.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import Foundation

struct HomePage {
    var chips: [Chip]
    var sections: [Section]
    var continuation: String?

    struct Chip: Hashable {
        var title: String
        var params: String?
        var deselectParams: String?
    }

    struct Section {
        var title: String
        var label: String?
        var thumbnailUrl: String?
        var browseEndpoint: (browseId: String, params: String?)?
        var items: [YTItem]

        var isSongsOnly: Bool {
            !items.isEmpty && items.allSatisfy {
                if case .song = $0 { true } else { false }
            }
        }
    }
}

enum HomeSection: Identifiable {
    case quickPicks(items: [YTItem])
    case keepListening(items: [YTItem])
    case forgottenFavorites(items: [YTItem])
    case homePageSection(HomePage.Section, index: Int)
    case accountPlaylists(items: [YTItem])
    case similarRecommendation(items: [YTItem], title: String)
    case dailyDiscover(items: [YTItem])
    case fromTheCommunity(items: [YTItem])
    case speedDial(items: [YTItem])
    case moodAndGenres(items: [YTItem])

    var id: String {
        switch self {
        case .quickPicks: return "quick_picks"
        case .keepListening: return "keep_listening"
        case .forgottenFavorites: return "forgotten_favorites"
        case .homePageSection(_, let index): return "homepage_\(index)"
        case .accountPlaylists: return "account_playlists"
        case .similarRecommendation(_, let title): return "similar_\(title)"
        case .dailyDiscover: return "daily_discover"
        case .fromTheCommunity: return "from_the_community"
        case .speedDial: return "speed_dial"
        case .moodAndGenres: return "mood_and_genres"
        }
    }

    var displayTitle: String {
        switch self {
        case .quickPicks: return "Quick Picks"
        case .keepListening: return "Keep Listening"
        case .forgottenFavorites: return "Forgotten Favorites"
        case .homePageSection(let section, _): return section.title
        case .accountPlaylists: return "Your Playlists"
        case .similarRecommendation(_, let title): return title
        case .dailyDiscover: return "Daily Discover"
        case .fromTheCommunity: return "From the Community"
        case .speedDial: return "Speed Dial"
        case .moodAndGenres: return "Mood & Genres"
        }
    }

    var items: [YTItem] {
        switch self {
        case .quickPicks(let items): return items
        case .keepListening(let items): return items
        case .forgottenFavorites(let items): return items
        case .homePageSection(let section, _): return section.items
        case .accountPlaylists(let items): return items
        case .similarRecommendation(let items, _): return items
        case .dailyDiscover(let items): return items
        case .fromTheCommunity(let items): return items
        case .speedDial(let items): return items
        case .moodAndGenres(let items): return items
        }
    }

    var isSongsOnly: Bool {
        switch self {
        case .homePageSection(let section, _): return section.isSongsOnly
        default: return false
        }
    }
}
