//
//  HomePageParser.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import Foundation

enum HomePageParser {
    static func parseHomePage(from json: [String: Any]) -> HomePage? {
        guard let contents = json["contents"] as? [String: Any],
              let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = singleColumn["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let sectionList = content["sectionListRenderer"] as? [String: Any] else {
            return nil
        }

        let chips = parseChips(from: sectionList)
        let sections = parseSections(from: sectionList)
        let continuation = extractContinuation(from: sectionList)

        return HomePage(chips: chips, sections: sections, continuation: continuation)
    }

    static func parseContinuationSections(from json: [String: Any]) -> (sections: [HomePage.Section], continuation: String?)? {
        guard let continuationContents = json["continuationContents"] as? [String: Any],
              let sectionList = continuationContents["sectionListContinuation"] as? [String: Any] else {
            return nil
        }

        let sections = parseSections(from: sectionList)
        let continuation = extractContinuation(from: sectionList)
        return (sections, continuation)
    }
}

// MARK: - Chips

extension HomePageParser {
    static func parseChips(from sectionList: [String: Any]) -> [HomePage.Chip] {
        guard let header = sectionList["header"] as? [String: Any],
              let chipCloud = header["chipCloudRenderer"] as? [String: Any],
              let chips = chipCloud["chips"] as? [[String: Any]] else {
            return []
        }
        return chips.compactMap { chipDict in
            guard let chipRenderer = chipDict["chipCloudChipRenderer"] as? [String: Any] else { return nil }
            let title = extractRunsText(chipRenderer["text"] as? [String: Any]) ?? ""
            let nav = chipRenderer["navigationEndpoint"] as? [String: Any]
            let params = (nav?["browseEndpoint"] as? [String: Any])?["params"] as? String
            let deselect = chipRenderer["onDeselectedCommand"] as? [String: Any]
            let deselectParams = (deselect?["browseEndpoint"] as? [String: Any])?["params"] as? String
            return HomePage.Chip(title: title, params: params, deselectParams: deselectParams)
        }
    }
}

// MARK: - Sections

extension HomePageParser {
    static func parseSections(from sectionList: [String: Any]) -> [HomePage.Section] {
        guard let contents = sectionList["contents"] as? [[String: Any]] else { return [] }
        return contents.compactMap { parseSection(from: $0) }
    }

    static func parseSection(from contentDict: [String: Any]) -> HomePage.Section? {
        guard let carousel = contentDict["musicCarouselShelfRenderer"] as? [String: Any] else { return nil }
        return parseCarouselSection(from: carousel)
    }

    static func parseCarouselSection(from carousel: [String: Any]) -> HomePage.Section? {
        guard let header = carousel["header"] as? [String: Any],
              let basicHeader = header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any],
              let title = extractRunsText(basicHeader["title"] as? [String: Any]) else {
            return nil
        }

        let label = extractRunsText(basicHeader["strapline"] as? [String: Any])
        let thumbnailUrl = extractHeaderThumbnail(basicHeader)
        let browseEndpoint = extractBrowseEndpoint(basicHeader)
        let items = parseItems(from: carousel["contents"] as? [[String: Any]] ?? [])

        guard !items.isEmpty else { return nil }

        return HomePage.Section(
            title: title,
            label: label,
            thumbnailUrl: thumbnailUrl,
            browseEndpoint: browseEndpoint,
            items: items
        )
    }

    static func parseItems(from contents: [[String: Any]]) -> [YTItem] {
        contents.compactMap { itemDict in
            if let twoRow = itemDict["musicTwoRowItemRenderer"] as? [String: Any] {
                return parseTwoRowItem(twoRow)
            }
            if let responsiveList = itemDict["musicResponsiveListItemRenderer"] as? [String: Any] {
                return SongItem.from(responsiveList).map { YTItem.song($0) }
            }
            return nil
        }
    }

    static func parseTwoRowItem(_ renderer: [String: Any]) -> YTItem? {
        let pageType = extractPageType(renderer)
        let hasWatchEndpoint = hasWatchEndpoint(renderer)

        if hasWatchEndpoint && pageType == nil {
            return SongItem.from(renderer).map { YTItem.song($0) }
        }
        switch pageType {
        case "MUSIC_PAGE_TYPE_ALBUM", "MUSIC_PAGE_TYPE_AUDIOBOOK":
            return AlbumItem.from(renderer).map { YTItem.album($0) }
        case "MUSIC_PAGE_TYPE_ARTIST":
            return ArtistItem.from(renderer).map { YTItem.artist($0) }
        case "MUSIC_PAGE_TYPE_PLAYLIST":
            return PlaylistItem.from(renderer).map { YTItem.playlist($0) }
        case "MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE":
            return PodcastItem.from(renderer).map { YTItem.podcast($0) }
        case "MUSIC_PAGE_TYPE_NON_MUSIC_AUDIO_TRACK_PAGE":
            return EpisodeItem.from(renderer).map { YTItem.episode($0) }
        default:
            return nil
        }
    }
}

// MARK: - Extract Helpers

extension HomePageParser {
    static func extractPageType(_ renderer: [String: Any]) -> String? {
        guard let nav = renderer["navigationEndpoint"] as? [String: Any],
              let browse = nav["browseEndpoint"] as? [String: Any],
              let configs = browse["browseEndpointContextSupportedConfigs"] as? [String: Any],
              let musicConfig = configs["browseEndpointContextMusicConfig"] as? [String: Any],
              let pageType = musicConfig["pageType"] as? String else { return nil }
        return pageType
    }

    static func hasWatchEndpoint(_ renderer: [String: Any]) -> Bool {
        guard let nav = renderer["navigationEndpoint"] as? [String: Any] else { return false }
        return nav["watchEndpoint"] != nil
    }

    static func extractBrowseEndpoint(_ header: [String: Any]) -> (browseId: String, params: String?)? {
        guard let moreContent = header["moreContentButton"] as? [String: Any],
              let button = moreContent["buttonRenderer"] as? [String: Any],
              let nav = button["navigationEndpoint"] as? [String: Any],
              let browse = nav["browseEndpoint"] as? [String: Any],
              let browseId = browse["browseId"] as? String else { return nil }
        return (browseId, browse["params"] as? String)
    }

    static func extractHeaderThumbnail(_ header: [String: Any]) -> String? {
        guard let thumbnail = header["thumbnail"] as? [String: Any],
              let thumbnails = thumbnail["thumbnails"] as? [[String: Any]],
              let last = thumbnails.last,
              let url = last["url"] as? String else { return nil }
        return url
    }

    static func extractContinuation(from sectionList: [String: Any]) -> String? {
        guard let continuations = sectionList["continuations"] as? [[String: Any]],
              let first = continuations.first,
              let nextContinuation = first["nextContinuationData"] as? [String: Any],
              let token = nextContinuation["continuation"] as? String else { return nil }
        return token
    }
}

private func extractRunsText(_ dict: [String: Any]?) -> String? {
    guard let runs = dict?["runs"] as? [[String: Any]], let first = runs.first else { return nil }
    return first["text"] as? String
}
