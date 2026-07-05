//
// LibraryBrowseParser.swift
// Trop
//
// Created by 686udjie on 30/06/2026.
//

import Foundation

enum LibraryBrowseParser {
    // Navigates through the nested JSON to find the musicResponsiveListItemRenderer items.
    // Handles both first-page (sectionListRenderer) and continuation structures.
    static func extractItems(from json: [String: Any]) -> [[String: Any]]? {
        // Helper: try to get items from a content section, unwrapping itemSectionRenderer
        // Helper: extract items from any renderer dict
        func extractItemsFromRenderer(_ rendererVal: Any) -> [[String: Any]]? {
            if let dict = rendererVal as? [String: Any] {
                if let items = dict["contents"] as? [[String: Any]] { return items }
                if let items = dict["items"] as? [[String: Any]] { return items }
            }
            // Try as NSDictionary (some JSON values come as NSDictionary subclasses)
            if let nsDict = rendererVal as? NSDictionary as? [String: Any] {
                if let items = nsDict["contents"] as? [[String: Any]] { return items }
                if let items = nsDict["items"] as? [[String: Any]] { return items }
            }
            return nil
        }

        func itemsFrom(_ section: [String: Any]) -> [[String: Any]]? {
            // Try itemSectionRenderer wrapper first (most common in library pages)
            if let itemSection = section["itemSectionRenderer"] as? [String: Any],
               let itemContents = itemSection["contents"] as? [[String: Any]],
               let first = itemContents.first {
                return itemsFromContent(first)
            }
            return itemsFromContent(section)
        }

        // Helper: extract items from a content dict that may be musicShelfRenderer, gridRenderer, or musicPlaylistShelfRenderer
        func itemsFromContent(_ content: [String: Any]) -> [[String: Any]]? {
            for key in ["musicShelfRenderer", "gridRenderer", "musicPlaylistShelfRenderer"] {
                if let val = content[key], let items = extractItemsFromRenderer(val) { return items }
            }
            return nil
        }

        // Try singleColumnBrowseResultsRenderer path
        if let contents = json["contents"] as? [String: Any],
           let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumn["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let content = tabRenderer["content"] as? [String: Any],
           let sectionList = content["sectionListRenderer"] as? [String: Any],
           let sections = sectionList["contents"] as? [[String: Any]],
           let firstSection = sections.first,
           let items = itemsFrom(firstSection) {
            return items
        }
        // Try twoColumnBrowseResultsRenderer path (VLSE, VL* playlists)
        if let contents = json["contents"] as? [String: Any] {
            if let twoColumn = contents["twoColumnBrowseResultsRenderer"] as? [String: Any] {
                if let secondary = twoColumn["secondaryContents"] as? [String: Any] {
                    if let sectionList = secondary["sectionListRenderer"] as? [String: Any] {
                        if let sections = sectionList["contents"] as? [[String: Any]],
                           let firstSection = sections.first,
                           let items = itemsFrom(firstSection) {
                            return items
                        }
                    }
                }
            }
        }

        // Try flat contents structure (FEmusic_library_privately_owned_*)
        if let rawContents = json["contents"] {
            if let contentsArray = rawContents as? [[String: Any]],
               let first = contentsArray.first,
               let items = itemsFrom(first) { return items }
        }

        // Try continuationContents paths
        if let continuationContents = json["continuationContents"] as? [String: Any] {
            if let shelfCont = continuationContents["musicShelfContinuation"] as? [String: Any],
               let items = shelfCont["contents"] as? [[String: Any]] {
                return items
            }
            if let gridCont = continuationContents["gridContinuation"] as? [String: Any],
               let items = gridCont["items"] as? [[String: Any]] {
                return items
            }
            if let playlistCont = continuationContents["musicPlaylistShelfContinuation"] as? [String: Any],
               let items = playlistCont["contents"] as? [[String: Any]] {
                return items
            }
        }
        return nil
    }

    static func extractContinuationToken(from json: [String: Any]) -> String? {
        // Helper: unwrap itemSectionRenderer to get the actual renderer
        func unwrapSection(_ section: [String: Any]) -> [String: Any] {
            if let itemSection = section["itemSectionRenderer"] as? [String: Any],
               let contents = itemSection["contents"] as? [[String: Any]],
               let first = contents.first,
               let shelf = first["musicShelfRenderer"] as? [String: Any] { return shelf }
            if let itemSection = section["itemSectionRenderer"] as? [String: Any],
               let contents = itemSection["contents"] as? [[String: Any]],
               let first = contents.first,
               let grid = first["gridRenderer"] as? [String: Any] { return grid }
            if let itemSection = section["itemSectionRenderer"] as? [String: Any],
               let contents = itemSection["contents"] as? [[String: Any]],
               let first = contents.first,
               let playlistShelf = first["musicPlaylistShelfRenderer"] as? [String: Any] { return playlistShelf }
            return section
        }

        // Helper to get continuation token
        func getToken(from renderer: [String: Any]) -> String? {
            guard let continuations = renderer["continuations"] as? [[String: Any]],
                  let first = continuations.first,
                  let nextContinuationData = first["nextContinuationData"] as? [String: Any],
                  let token = nextContinuationData["continuation"] as? String else { return nil }
            return token
        }

        // Try singleColumn path
        if let contents = json["contents"] as? [String: Any],
           let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumn["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let content = tabRenderer["content"] as? [String: Any],
           let sectionList = content["sectionListRenderer"] as? [String: Any],
           let sections = sectionList["contents"] as? [[String: Any]] {
            for section in sections {
                let unwrapped = unwrapSection(section)
                if let token = getToken(from: unwrapped) { return token }
            }
        }

        // Try twoColumn path
        if let contents = json["contents"] as? [String: Any],
           let twoColumn = contents["twoColumnBrowseResultsRenderer"] as? [String: Any],
           let secondary = twoColumn["secondaryContents"] as? [String: Any],
           let sectionList = secondary["sectionListRenderer"] as? [String: Any],
           let sections = sectionList["contents"] as? [[String: Any]] {
            for section in sections {
                let unwrapped = unwrapSection(section)
                if let token = getToken(from: unwrapped) { return token }
            }
        }

        // Try flat contents (privately owned)
        if let contentsArray = json["contents"] as? [[String: Any]] {
            for section in contentsArray {
                let unwrapped = unwrapSection(section)
                if let token = getToken(from: unwrapped) { return token }
            }
        }

        // Try continuationContents paths
        if let continuationContents = json["continuationContents"] as? [String: Any] {
            if let shelfCont = continuationContents["musicShelfContinuation"] as? [String: Any],
               let token = getToken(from: shelfCont) { return token }
            if let gridCont = continuationContents["gridContinuation"] as? [String: Any],
               let token = getToken(from: gridCont) { return token }
            if let playlistCont = continuationContents["musicPlaylistShelfContinuation"] as? [String: Any],
               let token = getToken(from: playlistCont) { return token }
        }

        return nil
    }
}

// MARK: Renderer extraction

extension LibraryBrowseParser {
    private static func renderer<T>(_ item: [String: Any], key: String) -> T? {
        item[key] as? T
    }

    private static func responsiveListItem(_ item: [String: Any]) -> [String: Any]? {
        item["musicResponsiveListItemRenderer"] as? [String: Any]
    }

    private static func flexText(_ item: [String: Any], index: Int) -> String? {
        guard let flexColumns = item["flexColumns"] as? [[String: Any]],
              index < flexColumns.count else { return nil }
        let column = flexColumns[index]
        let flexRenderer = column["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
        ?? column["musicResponsiveListItemColumnRenderer"] as? [String: Any]
        guard let runs = flexRenderer?["text"] as? [String: Any],
              let runsArray = runs["runs"] as? [[String: Any]],
              let firstRun = runsArray.first,
              let text = firstRun["text"] as? String else { return nil }
        return text
    }

    private static func allFlexTextRuns(_ item: [String: Any], index: Int) -> [String] {
        guard let flexColumns = item["flexColumns"] as? [[String: Any]],
              index < flexColumns.count else { return [] }
        let column = flexColumns[index]
        let flexRenderer = column["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
        ?? column["musicResponsiveListItemColumnRenderer"] as? [String: Any]
        guard let runs = flexRenderer?["text"] as? [String: Any],
              let runsArray = runs["runs"] as? [[String: Any]] else { return [] }
        return runsArray.compactMap { $0["text"] as? String }
    }

    private static func thumbnailUrl(_ item: [String: Any]) -> String? {
        guard let thumbnail = item["thumbnail"] as? [String: Any],
              let musicThumbnail = thumbnail["musicThumbnailRenderer"] as? [String: Any]
                ?? thumbnail["musicThumbnailRenderer"] as? [String: Any],
              let thumb = musicThumbnail["thumbnail"] as? [String: Any]
                ?? thumbnail["thumbnails"] as? [String: Any],
              let thumbnails = thumb["thumbnails"] as? [[String: Any]],
              let first = thumbnails.first,
              let url = first["url"] as? String else { return nil }
        return url
    }

    private static func menuItems(_ item: [String: Any]) -> [[String: Any]]? {
        guard let menu = item["menu"] as? [String: Any],
              let menuRenderer = menu["menuRenderer"] as? [String: Any],
              let items = menuRenderer["items"] as? [[String: Any]] else { return nil }
        return items
    }

    private static func twoRowItem(_ item: [String: Any]) -> [String: Any]? {
        item["musicTwoRowItemRenderer"] as? [String: Any]
    }

    private static func twoRowTitle(_ item: [String: Any]) -> String? {
        guard let title = item["title"] as? [String: Any],
              let runs = title["runs"] as? [[String: Any]],
              let first = runs.first,
              let text = first["text"] as? String else { return nil }
        return text
    }

    private static func twoRowSubtitle(_ item: [String: Any]) -> String? {
        guard let subtitle = item["subtitle"] as? [String: Any],
              let runs = subtitle["runs"] as? [[String: Any]],
              let first = runs.first,
              let text = first["text"] as? String else { return nil }
        return text
    }

    private static func twoRowThumbnailUrl(_ item: [String: Any]) -> String? {
        // Try thumbnailRenderer.musicThumbnailRenderer.thumbnail.thumbnails
        if let thumbnailRenderer = item["thumbnailRenderer"] as? [String: Any],
           let musicThumbnail = thumbnailRenderer["musicThumbnailRenderer"] as? [String: Any],
           let thumbnail = musicThumbnail["thumbnail"] as? [String: Any],
           let thumbnails = thumbnail["thumbnails"] as? [[String: Any]],
           let first = thumbnails.first,
           let url = first["url"] as? String { return url }
        // Fallback: try thumbnail.musicThumbnailRenderer.thumbnail.thumbnails
        if let thumbnail = item["thumbnail"] as? [String: Any],
           let musicThumbnail = thumbnail["musicThumbnailRenderer"] as? [String: Any],
           let thumb = musicThumbnail["thumbnail"] as? [String: Any],
           let thumbnails = thumb["thumbnails"] as? [[String: Any]],
           let first = thumbnails.first,
           let url = first["url"] as? String { return url }
        return nil
    }

    private static func browseId(_ item: [String: Any]) -> String? {
        guard let nav = item["navigationEndpoint"] as? [String: Any],
              let browse = nav["browseEndpoint"] as? [String: Any],
              let bid = browse["browseId"] as? String else { return nil }
        return bid
    }

    private static func twoRowBrowseId(renderer: [String: Any], item: [String: Any]) -> String? {
        // Check inside renderer first
        if let nav = renderer["navigationEndpoint"] as? [String: Any] {
            if let browse = nav["browseEndpoint"] as? [String: Any],
               let bid = browse["browseId"] as? String { return bid }
            if let watch = nav["watchEndpoint"] as? [String: Any],
               let pid = watch["playlistId"] as? String { return pid }
        }
        // Fallback to item level
        if let nav = item["navigationEndpoint"] as? [String: Any] {
            if let browse = nav["browseEndpoint"] as? [String: Any],
               let bid = browse["browseId"] as? String { return bid }
            if let watch = nav["watchEndpoint"] as? [String: Any],
               let pid = watch["playlistId"] as? String { return pid }
        }
        return nil
    }

    private static func playlistId(_ item: [String: Any]) -> String? {
        guard let nav = item["navigationEndpoint"] as? [String: Any],
              let watch = nav["watchEndpoint"] as? [String: Any],
              let pid = watch["playlistId"] as? String else { return nil }
        return pid
    }
}

// MARK: Parsing helpers

private struct LibraryToggleState {
    var addToken: String?
    var removeToken: String?
    var isToggled: Bool
}

extension LibraryBrowseParser {
    private static func libraryTokens(_ item: [String: Any]) -> LibraryToggleState {
        guard let items = menuItems(item) else { return LibraryToggleState(addToken: nil, removeToken: nil, isToggled: false) }
        for menuItem in items {
            guard let toggle = menuItem["toggleMenuServiceItemRenderer"] as? [String: Any] else { continue }
            let defaultIcon = toggle["defaultIcon"] as? [String: Any]
            let defaultIconType = defaultIcon?["iconType"] as? String

            let defaultEndpoint = toggle["defaultServiceEndpoint"] as? [String: Any]
            let toggledEndpoint = toggle["toggledServiceEndpoint"] as? [String: Any]

            let defaultToken = feedbackToken(from: defaultEndpoint)
            let toggledToken = feedbackToken(from: toggledEndpoint)

            // Determine the current state based on the default icon type
            let isCurrentlyToggled: Bool
            if let defaultType = defaultIconType {
                let defaultIsRemove = defaultType.contains("REMOVE") || defaultType == "CHECK_CHECK"
                isCurrentlyToggled = defaultIsRemove
            } else {
                isCurrentlyToggled = false
            }

            if let defaultToken {
                return LibraryToggleState(addToken: defaultToken, removeToken: toggledToken, isToggled: isCurrentlyToggled)
            } else if let toggledToken {
                return LibraryToggleState(addToken: defaultToken, removeToken: toggledToken, isToggled: isCurrentlyToggled)
            }
        }
        return LibraryToggleState(addToken: nil, removeToken: nil, isToggled: false)
    }

    private static func feedbackToken(from endpoint: [String: Any]?) -> String? {
        guard let endpoint,
              let feedback = endpoint["feedbackEndpoint"] as? [String: Any],
              let token = feedback["feedbackToken"] as? String else { return nil }
        return token
    }

    private static func durationSeconds(_ item: [String: Any]) -> Int {
        // Duration may appear as a badge on the thumbnail or in the subtitle
        if let badges = item["badges"] as? [[String: Any]],
           let first = badges.first,
           let badge = first["musicInlineBadgeRenderer"] as? [String: Any],
           let runs = badge["text"] as? [String: Any],
           let runsArray = runs["runs"] as? [[String: Any]],
           let firstRun = runsArray.first,
           let text = firstRun["text"] as? String {
            return parseDuration(text)
        }
        // Fallback: check flex column subtitle for duration pattern
        let subtitleRuns = allFlexTextRuns(item, index: 1)
        for run in subtitleRuns {
            if run.contains(":") && run.count <= 8 {
                return parseDuration(run)
            }
        }
        return 0
    }

    private static func parseDuration(_ text: String) -> Int {
        let parts = text.split(separator: ":")
        guard !parts.isEmpty else { return 0 }
        if parts.count == 2 {
            return (Int(parts[0]) ?? 0) * 60 + (Int(parts[1]) ?? 0)
        } else if parts.count == 3 {
            return (Int(parts[0]) ?? 0) * 3600 + (Int(parts[1]) ?? 0) * 60 + (Int(parts[2]) ?? 0)
        }
        return Int(text) ?? 0
    }
}

// MARK: Item parsers

extension LibraryBrowseParser {
    static func parseSong(_ item: [String: Any]) -> ParsedSong? {
        guard let renderer = responsiveListItem(item) else { return nil }
        // videoId may be at renderer level or inside playlistItemData or navigationEndpoint.watchEndpoint
        let videoId: String
        if let vid = renderer["videoId"] as? String {
            videoId = vid
        } else if let pid = renderer["playlistItemData"] as? [String: Any],
                  let vid = pid["videoId"] as? String {
            videoId = vid
        } else if let nav = renderer["navigationEndpoint"] as? [String: Any],
                  let watch = nav["watchEndpoint"] as? [String: Any],
                  let vid = watch["videoId"] as? String {
            videoId = vid
        } else { return nil }
        let title = flexText(renderer, index: 0) ?? "Unknown"
        let artistsText = allFlexTextRuns(renderer, index: 1)
        let nonArtistLabels: Set<String> = ["song", "video", "track", "music", "podcast", "episode"]
        let conjunctions: Set<String> = [",", "&", "and", "feat.", "ft.", "featuring"]
        let artists = artistsText.filter {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            guard trimmed != " • " && !trimmed.hasPrefix("http") else { return false }
            if nonArtistLabels.contains(lower) { return false }
            if conjunctions.contains(lower) { return false }
            if lower.range(of: "^\\d+(\\.\\d+)?[KMBT]?\\s*(views|downloads|listeners|subscribers)$", options: [.regularExpression, .caseInsensitive]) != nil { return false }
            return true
        }
        let albumRun = allFlexTextRuns(renderer, index: 2).filter { $0 != " • " && !$0.hasPrefix("http") }
        let album = albumRun.first
        let tokens = libraryTokens(renderer)
        return ParsedSong(
            videoId: videoId,
            title: title,
            artists: artists,
            artistIds: [],
            album: album,
            albumId: nil,
            duration: durationSeconds(renderer),
            thumbnailUrl: thumbnailUrl(renderer),
            isLiked: tokens.isToggled,
            libraryAddToken: tokens.addToken,
            libraryRemoveToken: tokens.removeToken
        )
    }

    static func parseAlbum(_ item: [String: Any]) -> ParsedAlbum? {
        // Try musicResponsiveListItemRenderer (shelf view)
        if let renderer = responsiveListItem(item),
           let bid = browseId(renderer) {
            let title = flexText(renderer, index: 0) ?? "Unknown"
            let subtitleRuns = allFlexTextRuns(renderer, index: 1)
            let artist = subtitleRuns.first(where: { $0 != " • " && !$0.hasPrefix("http") })
            var songCount = 0
            var duration = 0
            for run in subtitleRuns {
                if run.contains("song") || run.contains("Songs") || run.contains("tracks") {
                    let num = run.trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? ""
                    songCount = Int(num) ?? 0
                }
                if run.contains(":") {
                    duration = parseDuration(run)
                }
            }
            return ParsedAlbum(
                browseId: bid,
                title: title,
                artist: artist,
                thumbnailUrl: thumbnailUrl(renderer),
                songCount: songCount,
                duration: duration,
                playlistId: playlistId(renderer)
            )
        }

        // Try musicTwoRowItemRenderer (grid view)
        if let renderer = twoRowItem(item),
           let bid = twoRowBrowseId(renderer: renderer, item: item) {
            let title = twoRowTitle(renderer) ?? "Unknown"
            let artist = twoRowSubtitle(renderer)
            return ParsedAlbum(
                browseId: bid,
                title: title,
                artist: artist,
                thumbnailUrl: twoRowThumbnailUrl(renderer),
                songCount: 0,
                duration: 0,
                playlistId: nil
            )
        }
        return nil
    }

    static func parseArtist(_ item: [String: Any]) -> ParsedArtist? {
        // Try musicResponsiveListItemRenderer (shelf view)
        if let renderer = responsiveListItem(item),
           let bid = browseId(renderer) {
            let title = flexText(renderer, index: 0) ?? "Unknown"
            let tokens = libraryTokens(renderer)
            return ParsedArtist(
                browseId: bid,
                name: title,
                thumbnailUrl: thumbnailUrl(renderer),
                isSubscribed: tokens.isToggled,
                channelId: bid
            )
        }

        // Try musicTwoRowItemRenderer (grid view)
        if let renderer = twoRowItem(item),
           let bid = twoRowBrowseId(renderer: renderer, item: item) {
            let title = twoRowTitle(renderer) ?? "Unknown"
            return ParsedArtist(
                browseId: bid,
                name: title,
                thumbnailUrl: twoRowThumbnailUrl(renderer),
                isSubscribed: false,
                channelId: bid
            )
        }
        return nil
    }

    static func parsePlaylist(_ item: [String: Any]) -> ParsedPlaylist? {
        // Try musicResponsiveListItemRenderer (shelf view)
        if let renderer = responsiveListItem(item),
           let bid = browseId(renderer) {
            let title = flexText(renderer, index: 0) ?? "Unknown"
            let subtitleRuns = allFlexTextRuns(renderer, index: 1)
            var songCount: Int?
            for run in subtitleRuns {
                if let num = Int(run.trimmingCharacters(in: .whitespaces)) {
                    songCount = num
                    break
                }
            }
            return ParsedPlaylist(
                browseId: bid,
                title: title,
                songCount: songCount,
                thumbnailUrl: thumbnailUrl(renderer)
            )
        }

        // Try musicTwoRowItemRenderer (grid view)
        if let renderer = twoRowItem(item),
           let bid = twoRowBrowseId(renderer: renderer, item: item) {
            let title = twoRowTitle(renderer) ?? "Unknown"
            return ParsedPlaylist(
                browseId: bid,
                title: title,
                songCount: nil,
                thumbnailUrl: twoRowThumbnailUrl(renderer)
            )
        }
        return nil
    }
}

// MARK: Podcast & Episode parsers

extension LibraryBrowseParser {
    static func parsePodcast(_ item: [String: Any]) -> ParsedPodcast? {
        guard let renderer = responsiveListItem(item),
              let bid = browseId(renderer) else { return nil }
        let title = flexText(renderer, index: 0) ?? "Unknown"
        let tokens = libraryTokens(renderer)
        return ParsedPodcast(
            browseId: bid,
            name: title,
            thumbnailUrl: thumbnailUrl(renderer),
            isSubscribed: tokens.isToggled
        )
    }

    static func parseEpisode(_ item: [String: Any]) -> ParsedEpisode? {
        guard let renderer = responsiveListItem(item),
              let videoId = renderer["videoId"] as? String else { return nil }
        let title = flexText(renderer, index: 0) ?? "Unknown"
        let tokens = libraryTokens(renderer)
        let subtitleRuns = allFlexTextRuns(renderer, index: 1)
        let podcastName = subtitleRuns.first(where: { $0 != " • " && !$0.hasPrefix("http") })
        // The podcastId might come from navigation endpoint or playlistId
        let pid = playlistId(renderer)
        return ParsedEpisode(
            videoId: videoId,
            title: title,
            duration: durationSeconds(renderer),
            thumbnailUrl: thumbnailUrl(renderer),
            podcastId: pid,
            podcastName: podcastName,
            isPlayed: false,
            savedAt: tokens.isToggled ? Date() : nil
        )
    }
}

// MARK: Convenience parsers

extension LibraryBrowseParser {
    static func parseSongs(from response: [String: Any]) -> [ParsedSong] {
        guard let items = extractItems(from: response) else { return [] }
        return items.compactMap { parseSong($0) }
    }

    static func parseAlbums(from response: [String: Any]) -> [ParsedAlbum] {
        guard let items = extractItems(from: response) else { return [] }
        return items.compactMap { parseAlbum($0) }
    }

    static func parseArtists(from response: [String: Any]) -> [ParsedArtist] {
        guard let items = extractItems(from: response) else { return [] }
        return items.compactMap { parseArtist($0) }
    }

    static func parsePlaylists(from response: [String: Any]) -> [ParsedPlaylist] {
        guard let items = extractItems(from: response) else { return [] }
        return items.compactMap { parsePlaylist($0) }
    }

    static func parsePodcasts(from response: [String: Any]) -> [ParsedPodcast] {
        guard let items = extractItems(from: response) else { return [] }
        return items.compactMap { parsePodcast($0) }
    }

    static func parseEpisodes(from response: [String: Any]) -> [ParsedEpisode] {
        guard let items = extractItems(from: response) else { return [] }
        return items.compactMap { parseEpisode($0) }
    }
}
