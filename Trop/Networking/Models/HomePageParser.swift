//
//  HomePageParser.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import Foundation

enum HomePageParser {
    static func parseHomePage(from json: [String: Any]) -> HomePage? {
        guard let sectionList = BrowseLens.sectionList(json) else {
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
            let title = InnerTubeJSON.runsText(chipRenderer["text"] as? [String: Any]) ?? ""
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
              let title = InnerTubeJSON.runsText(basicHeader["title"] as? [String: Any]) else {
            return nil
        }

        let label = InnerTubeJSON.runsText(basicHeader["strapline"] as? [String: Any])
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

// MARK: - Explore

extension HomePageParser {
    static let exploreBrowseId = "FEmusic_explore"
    static let moodsCategoryBrowseId = "FEmusic_moods_and_genres_category"

    /// Parses `FEmusic_explore` into categorized sections. Logs the raw
    /// structure at every level so the mapping can be tailored from logs:
    /// renderer keys per section, header browseIds, item counts and the
    /// first item's renderer keys.
    static func parseExploreSections(from json: [String: Any]) -> [ExploreSection] {
        guard let contents = json["contents"] as? [String: Any] else {
            Log.explore.error("Explore parse failed: missing contents, top keys=\(json.keys.sorted())")
            return []
        }
        guard let sections = BrowseLens.browseSections(json) else {
            Log.explore.error("Explore parse failed: bad section path, contents keys=\(contents.keys.sorted())")
            return []
        }
        Log.explore.debug("Explore raw: \(sections.count) sections")
        var output: [ExploreSection] = []
        for (index, sectionDict) in sections.enumerated() {
            let keys = sectionDict.keys.sorted()
            Log.explore.debug("Explore section[\(index)] keys=\(keys)")
            if let parsed = parseExploreSection(sectionDict, index: index) {
                output.append(parsed)
            }
        }
        Log.explore.debug(
            "Explore parsed: " + output.map { "\($0.title):\($0.items.count)+\($0.moods.count)moods" }.joined(separator: ", ")
        )
        return output
    }

    private static func parseExploreSection(
        _ sectionDict: [String: Any],
        index: Int
    ) -> ExploreSection? {
        if let carousel = sectionDict["musicCarouselShelfRenderer"] as? [String: Any] {
            return parseExploreCarousel(carousel, index: index)
        }
        if let shelf = sectionDict["musicShelfRenderer"] as? [String: Any] {
            let title = shelfTitle(shelf) ?? "Songs"
            let items = parseItems(from: shelf["contents"] as? [[String: Any]] ?? [])
            Log.explore.debug("Explore section[\(index)] shelf title='\(title)' items=\(items.count)")
            guard !items.isEmpty else { return nil }
            return ExploreSection(title: title, kind: .rows, items: items, moods: [])
        }
        if let immersive = sectionDict["musicImmersiveCarouselShelfRenderer"] as? [String: Any] {
            let contents = immersive["contents"] as? [[String: Any]] ?? []
            let items = parseItems(from: contents)
            Log.explore.debug(
                "Explore section[\(index)] immersive keys=\((immersive.keys.sorted())) items=\(items.count)"
            )
            guard !items.isEmpty else { return nil }
            return ExploreSection(title: "Featured", kind: .cards, items: items, moods: [])
        }
        if let grid = sectionDict["gridRenderer"] as? [String: Any] {
            let rawItems = grid["items"] as? [[String: Any]] ?? []
            let items = parseItems(from: rawItems)
            Log.explore.debug(
                "Explore section[\(index)] grid keys=\(grid.keys.sorted()) items=\(items.count) " +
                "first=\(rawItems.first?.keys.sorted() ?? [])"
            )
            guard !items.isEmpty else { return nil }
            return ExploreSection(title: "More", kind: .cards, items: items, moods: [])
        }
        return nil
    }

    private static func parseExploreCarousel(
        _ carousel: [String: Any],
        index: Int
    ) -> ExploreSection? {
        guard let header = carousel["header"] as? [String: Any],
              let basicHeader = header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any],
              let title = InnerTubeJSON.runsText(basicHeader["title"] as? [String: Any]) else {
            Log.explore.debug("Explore section[\(index)] carousel skipped: no basic header")
            return nil
        }
        let headerBrowseId = exploreHeaderBrowseId(basicHeader)
        let rawItems = carousel["contents"] as? [[String: Any]] ?? []
        Log.explore.debug(
            "Explore section[\(index)] carousel title='\(title)' browseId=\(headerBrowseId ?? "none") rawItems=\(rawItems.count)"
        )

        // Moods & genres: title + params shortcuts, no playable items.
        if headerBrowseId == "FEmusic_moods_and_genres" {
            let moods = rawItems.compactMap { parseMood(from: $0, sectionIndex: index) }
            Log.explore.debug("Explore section[\(index)] moods parsed=\(moods.count)")
            guard !moods.isEmpty else { return nil }
            return ExploreSection(title: title, kind: .moods, items: [], moods: moods)
        }

        let items = parseItems(from: rawItems)
        if let first = rawItems.first {
            Log.explore.debug("Explore section[\(index)] first item keys=\(first.keys.sorted()) parsed=\(items.count)")
        }
        if items.isEmpty, !rawItems.isEmpty {
            // Shelf dropped: log why the first item didn't parse so the
            // shape can be mapped (pageType / browse prefix / endpoints).
            Log.explore.debug("Explore section[\(index)] dropped: " + describeUnparsed(rawItems.first ?? [:]))
        }
        guard !items.isEmpty else { return nil }

        // Videos and chart shelves have machine-readable header browseIds;
        // anything song-only renders as rows, mixed content as cards.
        let kind: ExploreSection.Kind
        if headerBrowseId == "FEmusic_new_releases_videos"
            || headerBrowseId?.hasPrefix("VLPL") == true
            || headerBrowseId?.hasPrefix("VLOLA") == true
            || items.allSatisfy({ if case .song = $0 { true } else { false } }) {
            kind = .rows
        } else {
            kind = .cards
        }
        return ExploreSection(title: title, kind: kind, items: items, moods: [])
    }

    /// Header identity per ytmusic-rs: the title runs' navigation endpoint,
    /// falling back to the more-content button.
    private static func exploreHeaderBrowseId(_ basicHeader: [String: Any]) -> String? {
        if let title = basicHeader["title"] as? [String: Any],
           let runs = title["runs"] as? [[String: Any]],
           let first = runs.first,
           let nav = first["navigationEndpoint"] as? [String: Any],
           let browse = nav["browseEndpoint"] as? [String: Any],
           let bid = browse["browseId"] as? String {
            return bid
        }
        return extractBrowseEndpoint(basicHeader)?.browseId
    }

    private static func shelfTitle(_ shelf: [String: Any]) -> String? {
        guard let header = shelf["header"] as? [String: Any],
              let basicHeader = header["musicShelfHeaderRenderer"] as? [String: Any] else { return nil }
        return InnerTubeJSON.runsText(basicHeader["title"] as? [String: Any])
    }

    /// Best-effort mood shortcut parsing (title + category params).
    /// Raw item keys are logged so unknown shapes can be mapped later.
    private static func parseMood(from item: [String: Any], sectionIndex: Int) -> MoodItem? {
        if let twoRow = item["musicTwoRowItemRenderer"] as? [String: Any] {
            let title = InnerTubeJSON.runsText(twoRow["title"] as? [String: Any])
            let params = moodParams(from: twoRow["navigationEndpoint"] as? [String: Any])
            if let title {
                return MoodItem(title: title, params: params)
            }
        }
        if let button = item["musicNavigationButtonRenderer"] as? [String: Any] {
            let title = InnerTubeJSON.runsText(button["buttonText"] as? [String: Any])
            let params = moodParams(from: button["clickCommand"] as? [String: Any])
            if let title {
                return MoodItem(title: title, params: params)
            }
        }
        Log.explore.debug("Explore section[\(sectionIndex)] unparsed mood keys=\(item.keys.sorted())")
        return nil
    }

    private static func moodParams(from endpoint: [String: Any]?) -> String? {
        guard let browse = endpoint?["browseEndpoint"] as? [String: Any],
              (browse["browseId"] as? String) == moodsCategoryBrowseId else { return nil }
        return browse["params"] as? String
    }

    /// One-line fingerprint of an unparseable item for log mapping.
    private static func describeUnparsed(_ item: [String: Any]) -> String {
        let inner: [String: Any]
        if let twoRow = item["musicTwoRowItemRenderer"] as? [String: Any] {
            inner = twoRow
        } else if let responsive = item["musicResponsiveListItemRenderer"] as? [String: Any] {
            inner = responsive
        } else {
            return "keys=\(item.keys.sorted())"
        }
        let pageType = extractPageType(inner) ?? "none"
        let nav = inner["navigationEndpoint"] as? [String: Any]
        let watch = nav?["watchEndpoint"] as? [String: Any]
        let browse = nav?["browseEndpoint"] as? [String: Any]
        return "renderer=\(item.keys.sorted()) pageType=\(pageType) " +
            "watch=\(watch?["videoId"] as? String ?? "none") " +
            "browse=\(browse?["browseId"] as? String ?? "none")"
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
