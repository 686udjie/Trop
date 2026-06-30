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
        if let contents = json["contents"] as? [String: Any],
           let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumn["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let content = tabRenderer["content"] as? [String: Any],
           let sectionList = content["sectionListRenderer"] as? [String: Any],
           let sections = sectionList["contents"] as? [[String: Any]],
           let firstSection = sections.first,
           let shelfRenderer = firstSection["musicShelfRenderer"] as? [String: Any],
           let items = shelfRenderer["contents"] as? [[String: Any]] {
            return items
        }
        if let continuationContents = json["continuationContents"] as? [String: Any],
           let shelfContinuation = continuationContents["musicShelfContinuation"] as? [String: Any],
           let items = shelfContinuation["contents"] as? [[String: Any]] {
            return items
        }
        return nil
    }

    static func extractContinuationToken(from json: [String: Any]) -> String? {
        let continuations: [[String: Any]]?
        if let contents = json["contents"] as? [String: Any],
           let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumn["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let content = tabRenderer["content"] as? [String: Any],
           let sectionList = content["sectionListRenderer"] as? [String: Any],
           let sections = sectionList["contents"] as? [[String: Any]],
           let firstSection = sections.first,
           let shelfRenderer = firstSection["musicShelfRenderer"] as? [String: Any] {
            continuations = shelfRenderer["continuations"] as? [[String: Any]]
        } else if let continuationContents = json["continuationContents"] as? [String: Any],
                  let shelfContinuation = continuationContents["musicShelfContinuation"] as? [String: Any] {
            continuations = shelfContinuation["continuations"] as? [[String: Any]]
        } else {
            continuations = nil
        }
        guard let first = continuations?.first,
              let nextContinuationData = first["nextContinuationData"] as? [String: Any],
              let token = nextContinuationData["continuation"] as? String else {
            return nil
        }
        return token
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

    private static func browseId(_ item: [String: Any]) -> String? {
        guard let nav = item["navigationEndpoint"] as? [String: Any],
              let browse = nav["browseEndpoint"] as? [String: Any],
              let bid = browse["browseId"] as? String else { return nil }
        return bid
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
        guard let renderer = responsiveListItem(item),
              let videoId = renderer["videoId"] as? String else { return nil }
        let title = flexText(renderer, index: 0) ?? "Unknown"
        let artistsText = allFlexTextRuns(renderer, index: 1)
        let artists = artistsText.filter { $0 != " • " && !$0.hasPrefix("http") }
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
        guard let renderer = responsiveListItem(item),
              let bid = browseId(renderer) else { return nil }
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

    static func parseArtist(_ item: [String: Any]) -> ParsedArtist? {
        guard let renderer = responsiveListItem(item),
              let bid = browseId(renderer) else { return nil }
        let title = flexText(renderer, index: 0) ?? "Unknown"
        let tokens = libraryTokens(renderer)
        return ParsedArtist(
            browseId: bid,
            name: title,
            thumbnailUrl: thumbnailUrl(renderer),
            isSubscribed: tokens.isToggled
        )
    }

    static func parsePlaylist(_ item: [String: Any]) -> ParsedPlaylist? {
        guard let renderer = responsiveListItem(item),
              let bid = browseId(renderer) else { return nil }
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
}

// MARK: Convenience parsers

extension LibraryBrowseParser {
    static func parseSongs(from response: [String: Any]) -> [ParsedSong] {
        guard let items = extractItems(from: response) else { return [] }
        return items.compactMap { item in
            guard let renderer = responsiveListItem(item) else { return nil }
            return parseSong(renderer)
        }
    }

    static func parseAlbums(from response: [String: Any]) -> [ParsedAlbum] {
        guard let items = extractItems(from: response) else { return [] }
        return items.compactMap { item in
            guard let renderer = responsiveListItem(item) else { return nil }
            return parseAlbum(renderer)
        }
    }

    static func parseArtists(from response: [String: Any]) -> [ParsedArtist] {
        guard let items = extractItems(from: response) else { return [] }
        return items.compactMap { item in
            guard let renderer = responsiveListItem(item) else { return nil }
            return parseArtist(renderer)
        }
    }

    static func parsePlaylists(from response: [String: Any]) -> [ParsedPlaylist] {
        guard let items = extractItems(from: response) else { return [] }
        return items.compactMap { item in
            guard let renderer = responsiveListItem(item) else { return nil }
            return parsePlaylist(renderer)
        }
    }
}
