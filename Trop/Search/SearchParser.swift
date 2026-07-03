//
//  SearchParser.swift
//  Trop
//
//  Created by 686udjie on 03/07/2026.
//

import Foundation

struct SearchSection: Identifiable {
    let id = UUID()
    var title: String
    var items: [YTItem]
}

enum SearchParser {

    static func parseSearchResults(from json: [String: Any]) -> [SearchSection] {
        guard let contents = json["contents"] as? [String: Any] else { return [] }

        let sectionList: [[String: Any]]?

        if let tabbed = contents["tabbedSearchResultsRenderer"] as? [String: Any],
           let tabs = tabbed["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let content = tabRenderer["content"] as? [String: Any],
           let slr = content["sectionListRenderer"] as? [String: Any] {

            sectionList = slr["contents"] as? [[String: Any]]

        } else if let slr = contents["sectionListRenderer"] as? [String: Any] {
            sectionList = slr["contents"] as? [[String: Any]]
        } else {
            sectionList = nil
        }

        guard let list = sectionList else { return [] }

        var allSections: [SearchSection] = []

        for sectionDict in list {

            // MARK: Top result
            if let cardShelf = sectionDict["musicCardShelfRenderer"] as? [String: Any] {

                let basicHeader = (cardShelf["header"] as? [String: Any])?["musicCardShelfHeaderBasicRenderer"] as? [String: Any]
                let title = runsText(basicHeader?["title"]) ?? "Top result"

                var items: [YTItem] = []

                if let top = parseTopResult(from: cardShelf) {
                    items.append(top)
                }

                if let cardContents = cardShelf["contents"] as? [[String: Any]] {
                    for itemDict in cardContents {
                        if let renderer = itemDict["musicResponsiveListItemRenderer"] as? [String: Any],
                           let item = YTItem.fromResponsiveListItem(renderer),
                           items.first?.id != item.id {
                            items.append(item)
                        }
                    }
                }

                if !items.isEmpty {
                    allSections.append(SearchSection(title: title, items: items))
                }
            }

            // MARK: Shelf
            if let shelf = sectionDict["musicShelfRenderer"] as? [String: Any] {

                let items: [YTItem] = (shelf["contents"] as? [[String: Any]] ?? []).compactMap { dict in
                    guard let renderer = dict["musicResponsiveListItemRenderer"] as? [String: Any] else {
                        return nil
                    }
                    return YTItem.fromResponsiveListItem(renderer)
                }

                guard !items.isEmpty else { continue }

                if let title = runsText(shelf["title"]) {
                    allSections.append(SearchSection(title: title, items: items))
                } else {
                    allSections.append(contentsOf: groupItemsByType(items))
                }
            }

            // MARK: Fallback section
            if let itemSection = sectionDict["itemSectionRenderer"] as? [String: Any] {

                let items: [YTItem] = (itemSection["contents"] as? [[String: Any]] ?? []).compactMap { dict in
                    guard let renderer = dict["musicResponsiveListItemRenderer"] as? [String: Any] else {
                        return nil
                    }
                    return YTItem.fromResponsiveListItem(renderer)
                }

                if !items.isEmpty {
                    allSections.append(contentsOf: groupItemsByType(items))
                }
            }
        }

        let sectionOrder = [
            "Top result",
            "Songs",
            "Videos",
            "Albums",
            "Artists",
            "Playlists",
            "Podcasts",
            "Episodes",
            "Profiles"
        ]

        let grouped = Dictionary(grouping: allSections, by: { $0.title })

        return grouped.map { key, value in
            SearchSection(title: key, items: value.flatMap { $0.items })
        }
        .sorted {
            (sectionOrder.firstIndex(of: $0.title) ?? 999) <
            (sectionOrder.firstIndex(of: $1.title) ?? 999)
        }
    }

    // MARK: - Private

    private static func groupItemsByType(_ items: [YTItem]) -> [SearchSection] {
        var groups: [String: [YTItem]] = [:]

        for item in items {
            let key: String

            switch item {
            case .song: key = "Songs"
            case .album: key = "Albums"
            case .artist: key = "Artists"
            case .playlist: key = "Playlists"
            case .podcast: key = "Podcasts"
            case .episode: key = "Episodes"
            }

            groups[key, default: []].append(item)
        }

        return ["Songs", "Albums", "Artists", "Playlists", "Podcasts", "Episodes"].compactMap { name in
            guard let items = groups[name], !items.isEmpty else { return nil }
            return SearchSection(title: name, items: items)
        }
    }

    private static func parseTopResult(from cardShelf: [String: Any]) -> YTItem? {

        // ✅ FIX: no ?? operator (avoids tuple parsing crash)
        var nav: [String: Any]? = nil

        if let onTap = cardShelf["onTap"] as? [String: Any] {
            nav = onTap
        } else if let navigationEndpoint = cardShelf["navigationEndpoint"] as? [String: Any] {
            nav = navigationEndpoint
        }

        let title = runsText(cardShelf["title"]) ?? "Unknown"
        let thumbnailUrl = DetailParser.extractMusicThumbnail(cardShelf)

        if let watch = nav?["watchEndpoint"] as? [String: Any],
           let videoId = watch["videoId"] as? String {
            return .song(SongItem(
                videoId: videoId,
                title: title,
                artists: [],
                album: nil,
                duration: 0,
                thumbnailUrl: thumbnailUrl,
                isExplicit: false,
                playlistId: watch["playlistId"] as? String
            ))
        }

        guard let browse = nav?["browseEndpoint"] as? [String: Any],
              let browseId = browse["browseId"] as? String else { return nil }

        let supportedConfigs = browse["browseEndpointContextSupportedConfigs"] as? [String: Any]
        let musicConfig = supportedConfigs?["browseEndpointContextMusicConfig"] as? [String: Any]
        let pageType = musicConfig?["pageType"] as? String

        switch pageType {
        case "MUSIC_PAGE_TYPE_ALBUM", "MUSIC_PAGE_TYPE_AUDIOBOOK":
            return .album(AlbumItem(
                browseId: browseId,
                title: title,
                artists: [],
                year: nil,
                thumbnailUrl: thumbnailUrl,
                playlistId: nil,
                isExplicit: false
            ))

        case "MUSIC_PAGE_TYPE_ARTIST", "MUSIC_PAGE_TYPE_USER_CHANNEL":
            return .artist(ArtistItem(
                browseId: browseId,
                name: title,
                thumbnailUrl: thumbnailUrl,
                isSubscribed: false
            ))

        case "MUSIC_PAGE_TYPE_PLAYLIST":
            return .playlist(PlaylistItem(
                id: browseId.replacingOccurrences(of: "VL", with: ""),
                title: title,
                author: nil,
                thumbnailUrl: thumbnailUrl,
                songCount: nil
            ))

        case "MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE":
            return .podcast(PodcastItem(
                browseId: browseId,
                title: title,
                author: nil,
                thumbnailUrl: thumbnailUrl
            ))

        default:
            if browseId.hasPrefix("VL") {
                return .playlist(PlaylistItem(
                    id: browseId.replacingOccurrences(of: "VL", with: ""),
                    title: title,
                    author: nil,
                    thumbnailUrl: thumbnailUrl,
                    songCount: nil
                ))
            } else if browseId.hasPrefix("UC") || browseId.hasPrefix("MPCH") {
                return .artist(ArtistItem(
                    browseId: browseId,
                    name: title,
                    thumbnailUrl: thumbnailUrl,
                    isSubscribed: false
                ))
            } else if browseId.hasPrefix("MPREb_") {
                return .album(AlbumItem(
                    browseId: browseId,
                    title: title,
                    artists: [],
                    year: nil,
                    thumbnailUrl: thumbnailUrl,
                    playlistId: nil,
                    isExplicit: false
                ))
            }

            return nil
        }
    }

    private static func runsText(_ value: Any?) -> String? {
        guard let dict = value as? [String: Any],
              let runs = dict["runs"] as? [[String: Any]],
              let first = runs.first else { return nil }

        return first["text"] as? String
    }
}
