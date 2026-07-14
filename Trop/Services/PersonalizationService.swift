//
//  PersonalizationService.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import Foundation

actor PersonalizationService {
    nonisolated static let shared = PersonalizationService()
    private let db = DatabaseService.shared
    private let innerTube = InnerTube.shared

    // MARK: - Phase 1: Local sections (fast, load immediately)

    func buildQuickPicks() async -> HomeSection {
        guard let songs = try? await db.fetchLikedSongs(), !songs.isEmpty else {
            return .quickPicks(items: [])
        }
        let items = songs.shuffled().prefix(12).map { YTItem.song(SongItem(entity: $0)) }
        return .quickPicks(items: Array(items))
    }

    func buildKeepListening() async -> HomeSection {
        var items: [YTItem] = []

        if let recentSongs = try? await db.fetchRecentSongs(days: 30, limit: 6) {
            for song in recentSongs where items.count < 8 {
                items.append(.song(SongItem(entity: song)))
            }
        }

        if let albums = try? await db.fetchAlbums(limit: 4) {
            for album in albums where items.count < 12 {
                items.append(.album(AlbumItem(entity: album)))
            }
        }

        if let artists = try? await db.fetchArtists(limit: 4) {
            for artist in artists where items.count < 16 {
                items.append(.artist(ArtistItem(entity: artist)))
            }
        }

        return .keepListening(items: items)
    }

    func buildForgottenFavorites() async -> HomeSection {
        guard let songs = try? await db.fetchForgottenFavorites(days: 60, limit: 10), !songs.isEmpty else {
            return .forgottenFavorites(items: [])
        }
        let items = songs.map { YTItem.song(SongItem(entity: $0)) }
        return .forgottenFavorites(items: items)
    }

    // MARK: - Phase 2: API-based sections (load in background)

    func buildAccountPlaylists() async -> HomeSection {
        guard await isLoggedIn() else { return .accountPlaylists(items: []) }
        do {
            let json = try await innerTube.browse(browseId: "FEmusic_liked_playlists")
            let playlists = LibraryBrowseParser.parsePlaylists(from: json)
            let items = playlists.map {
                YTItem.playlist(PlaylistItem(
                    id: $0.browseId, title: $0.title,
                    author: nil, thumbnailUrl: $0.thumbnailUrl,
                    songCount: $0.songCount
                ))
            }
            return .accountPlaylists(items: items)
        } catch {
            return .accountPlaylists(items: [])
        }
    }

    func buildDailyDiscover() async -> HomeSection {
        guard await isLoggedIn() else { return .dailyDiscover(items: []) }
        guard let likedSongs = try? await db.fetchLikedSongs(), !likedSongs.isEmpty else {
            return .dailyDiscover(items: [])
        }

        let seeds = likedSongs.shuffled().prefix(3)
        var seenIds = Set<String>()
        var discovered: [YTItem] = []

        for song in seeds {
            guard discovered.count < 10 else { break }
            guard let radio = try? await fetchRadio(videoId: song.id),
                  !radio.songs.isEmpty else { continue }
            let related = radio.songs.map { YTItem.song($0) }
            for item in related {
                if let videoId = item.videoId, !seenIds.contains(videoId) {
                    seenIds.insert(videoId)
                    discovered.append(item)
                }
                if discovered.count >= 10 { break }
            }
        }

        return .dailyDiscover(items: discovered)
    }

    func buildSimilarRecommendations() async -> [HomeSection] {
        guard await isLoggedIn() else { return [] }
        guard let topArtists = try? await db.fetchArtists(limit: 3), !topArtists.isEmpty else {
            return []
        }

        var sections: [HomeSection] = []
        for artist in topArtists.prefix(3) {
            guard sections.count < 3 else { break }
            guard let related = try? await innerTube.browse(browseId: artist.id),
                  let items = parseRelatedItems(from: related), !items.isEmpty else { continue }
            sections.append(.similarRecommendation(items: items, title: "Similar to \(artist.name)"))
        }
        return sections
    }

    func buildFromTheCommunity() async -> HomeSection {
        guard await isLoggedIn() else { return .fromTheCommunity(items: []) }
        guard let topArtists = try? await db.fetchArtists(limit: 3), !topArtists.isEmpty else {
            return .fromTheCommunity(items: [])
        }

        var seenIds = Set<String>()
        var communityPlaylists: [YTItem] = []

        for artist in topArtists {
            guard communityPlaylists.count < 5 else { break }
            guard let json = try? await innerTube.browse(browseId: artist.id) else { continue }
            let playlists = extractCommunityPlaylists(from: json)
            for playlist in playlists {
                let pid = normalizePlaylistId(playlist.browseId)
                guard !seenIds.contains(pid) else { continue }
                seenIds.insert(pid)
                communityPlaylists.append(.playlist(PlaylistItem(
                    id: pid, title: playlist.title,
                    author: nil, thumbnailUrl: playlist.thumbnailUrl,
                    songCount: playlist.songCount
                )))
                if communityPlaylists.count >= 5 { break }
            }
        }

        return .fromTheCommunity(items: communityPlaylists)
    }

    // MARK: - Helpers

    private func isLoggedIn() async -> Bool {
        let store = CookieStore()
        return await store.isLoggedIn()
    }

    func fetchRadio(videoId: String) async throws -> (songs: [SongItem], currentIndex: Int) {
        let playlistId = "RDAMVM\(videoId)"
        let json = try await innerTube.next(videoId: videoId, playlistId: playlistId)
        let panel = try extractPlaylistPanel(from: json)
        var songs: [(SongItem, Bool)] = []
        for entry in panel.contents {
            guard songs.count < 50 else { break }
            if let renderer = entry["playlistPanelVideoRenderer"] as? [String: Any],
               let song = parsePlaylistPanelVideoRenderer(renderer) {
                songs.append((song, renderer["selected"] as? Bool ?? false))
            }
        }
        guard !songs.isEmpty else { throw NSError(domain: "fetchRadio", code: 1, userInfo: [:]) }
        let currentIndex = songs.firstIndex(where: { $0.1 }) ?? 0
        let resultSongs = songs.map(\.0)
        if let automixItems = await tryResolveAutomix(from: panel) {
            let deduped = automixItems.filter { a in !resultSongs.contains(where: { $0.videoId == a.videoId }) }
            return (resultSongs + deduped, currentIndex)
        }
        return (resultSongs, currentIndex)
    }

    private struct PlaylistPanel { let contents: [[String: Any]] }

    private func extractPlaylistPanel(from json: [String: Any]) throws -> PlaylistPanel {
        guard let contents = json["contents"] as? [String: Any],
              let singleColumn = contents["singleColumnMusicWatchNextResultsRenderer"] as? [String: Any],
              let tabbed = singleColumn["tabbedRenderer"] as? [String: Any],
              let watchNext = tabbed["watchNextTabbedResultsRenderer"] as? [String: Any],
              let tabs = watchNext["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let queueRenderer = content["musicQueueRenderer"] as? [String: Any],
              let queueContent = queueRenderer["content"] as? [String: Any],
              let playlistPanel = queueContent["playlistPanelRenderer"] as? [String: Any],
              let panelContents = playlistPanel["contents"] as? [[String: Any]] else {
            throw NSError(domain: "fetchRadio", code: 2, userInfo: [:])
        }
        return PlaylistPanel(contents: panelContents)
    }

    private func tryResolveAutomix(from panel: PlaylistPanel) async -> [SongItem]? {
        guard let lastEntry = panel.contents.last,
              let automix = lastEntry["automixPreviewVideoRenderer"] as? [String: Any],
              let content = automix["content"] as? [String: Any],
              let autoRenderer = content["automixPlaylistVideoRenderer"] as? [String: Any],
              let navEndpoint = autoRenderer["navigationEndpoint"] as? [String: Any],
              let watchPlaylist = navEndpoint["watchPlaylistEndpoint"] as? [String: Any],
              let playlistId = watchPlaylist["playlistId"] as? String else { return nil }
        let autoVideoId = watchPlaylist["videoId"] as? String
        guard let autoJson = try? await innerTube.next(videoId: autoVideoId, playlistId: playlistId),
              let autoPanel = try? extractPlaylistPanel(from: autoJson) else { return nil }
        var songs: [SongItem] = []
        for entry in autoPanel.contents {
            guard songs.count < 50 else { break }
            if let renderer = entry["playlistPanelVideoRenderer"] as? [String: Any],
               let song = parsePlaylistPanelVideoRenderer(renderer) { songs.append(song) }
        }
        return songs.isEmpty ? nil : songs
    }

    private func parsePlaylistPanelVideoRenderer(_ renderer: [String: Any]) -> SongItem? {
        guard let vid = renderer["videoId"] as? String else { return nil }
        let title = extractRunsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let bylineRuns = extractRawRuns(renderer["longBylineText"] as? [String: Any] ?? renderer["shortBylineText"] as? [String: Any])
        let artists = parseArtists(from: bylineRuns)
        let thumbnail = extractThumbnailFrom(renderer["thumbnail"] as? [String: Any])
        let duration = parseDurationFromRenderer(renderer)
        return SongItem(videoId: vid, title: title, artists: artists, duration: duration, thumbnailUrl: thumbnail, isExplicit: false)
    }

    private func parseArtists(from bylineRuns: [[String: Any]]) -> [YTArtist] {
        let nonArtistLabels: Set<String> = ["song", "video", "track", "music", "podcast", "episode"]
        let conjunctions: Set<String> = [",", "&", "and", "feat.", "ft.", "featuring"]
        return bylineRuns.compactMap { run in
            guard let text = run["text"] as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            if trimmed.isEmpty || trimmed == "•" || trimmed == "·" { return nil }
            if nonArtistLabels.contains(lower) { return nil }
            if conjunctions.contains(lower) { return nil }
            if lower.range(of: "^\\d+(\\.\\d+)?[KMBT]?\\s*(views|downloads|listeners|subscribers)$", options: [.regularExpression, .caseInsensitive]) != nil { return nil }
            if let nav = run["navigationEndpoint"] as? [String: Any],
               let browse = nav["browseEndpoint"] as? [String: Any],
               let bid = browse["browseId"] as? String,
               bid.hasPrefix("MPREb_") { return nil }
            return YTArtist(name: cleanArtistDisplay(trimmed))
        }
    }

    private func extractCommunityPlaylists(from json: [String: Any]) -> [ParsedPlaylist] {
        guard let contents = json["contents"] as? [String: Any],
              let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = singleColumn["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let sectionList = content["sectionListRenderer"] as? [String: Any],
              let sections = sectionList["contents"] as? [[String: Any]] else { return [] }

        var playlists: [ParsedPlaylist] = []
        for section in sections {
            guard playlists.count < 10 else { break }
            guard let shelf = section["musicShelfRenderer"] as? [String: Any],
                  let contents = shelf["contents"] as? [[String: Any]] else { continue }
            for entry in contents {
                guard playlists.count < 10 else { break }
                guard let renderer = entry["musicResponsiveListItemRenderer"] as? [String: Any] else { continue }
                guard let nav = renderer["navigationEndpoint"] as? [String: Any],
                      let browse = nav["browseEndpoint"] as? [String: Any],
                      let bid = browse["browseId"] as? String else { continue }
                let stripped = bid.hasPrefix("VL") ? String(bid.dropFirst(2)) : bid
                guard !stripped.hasPrefix("RD"),
                      !stripped.hasPrefix("OLAK"),
                      !stripped.hasPrefix("MPREb_") else { continue }
                if let playlist = LibraryBrowseParser.parsePlaylist(entry) {
                    playlists.append(playlist)
                }
            }
        }
        return playlists
    }

    private func normalizePlaylistId(_ id: String) -> String {
        id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
    }

    private func parseRelatedItems(from json: [String: Any]) -> [YTItem]? {
        guard let contents = json["contents"] as? [String: Any],
              let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = singleColumn["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let sectionList = content["sectionListRenderer"] as? [String: Any],
              let sections = sectionList["contents"] as? [[String: Any]] else { return nil }

        var items: [YTItem] = []
        for section in sections {
            guard let shelf = section["musicShelfRenderer"] as? [String: Any],
                  let contents = shelf["contents"] as? [[String: Any]] else { continue }
            for entry in contents {
                if items.count >= 10 { break }
                if let renderer = entry["musicResponsiveListItemRenderer"] as? [String: Any] {
                    if let song = SongItem.from(renderer) {
                        items.append(.song(song))
                    }
                }
            }
        }
        return items.isEmpty ? nil : items
    }
}

private func extractRunsText(_ dict: [String: Any]?) -> String? {
    guard let runs = dict?["runs"] as? [[String: Any]], let first = runs.first else { return nil }
    return first["text"] as? String
}

private func extractRunsTextArray(_ dict: [String: Any]?) -> [String] {
    guard let runs = dict?["runs"] as? [[String: Any]] else { return [] }
    return runs.compactMap { $0["text"] as? String }
        .filter { $0 != " • " && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
}

private func extractThumbnailFrom(_ dict: [String: Any]?) -> String? {
    guard let thumb = dict?["thumbnails"] as? [[String: Any]],
          let last = thumb.last,
          let url = last["url"] as? String else { return nil }
    return url
}

private func extractRawRuns(_ dict: [String: Any]?) -> [[String: Any]] {
    guard let runs = dict?["runs"] as? [[String: Any]] else { return [] }
    return runs
}
