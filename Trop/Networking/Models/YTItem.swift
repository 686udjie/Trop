//
//  YTItem.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import Foundation

struct YTArtist {
    var name: String
    var id: String?
}

extension Int {
    var formattedDuration: String {
        guard self > 0 else { return "" }
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let secs = self % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", secs))"
        }
        return "\(minutes):\(String(format: "%02d", secs))"
    }
}

func parseDurationFromRenderer(_ renderer: [String: Any]) -> Int {
    // 1. fixedColumns[0] — primary source for MusicResponsiveListItemRenderer
    if let fixedColumns = renderer["fixedColumns"] as? [[String: Any]] {
        for col in fixedColumns {
            if let fixed = col["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any],
               let textDict = fixed["text"] as? [String: Any],
               let runs = textDict["runs"] as? [[String: Any]],
               let first = runs.first,
               let text = first["text"] as? String,
               let parsed = parseTime(text) {
                return parsed
            }
        }
    }

    // 2. lengthSeconds — raw seconds string from player response
    if let lengthSeconds = renderer["lengthSeconds"] as? String, let seconds = Int(lengthSeconds) {
        return seconds
    }
    if let lengthSeconds = renderer["lengthSeconds"] as? Int {
        return lengthSeconds
    }

    // 3. lengthText — used by PlaylistPanelVideoRenderer (up next / queue)
    if let lengthText = renderer["lengthText"] as? [String: Any],
       let runs = lengthText["runs"] as? [[String: Any]],
       let first = runs.first,
       let text = first["text"] as? String,
       let parsed = parseTime(text) {
        return parsed
    }

    // 4. Badges — thumbnail badges with duration
    if let badges = renderer["badges"] as? [[String: Any]] {
        for badgeDict in badges {
            if let badge = badgeDict["musicInlineBadgeRenderer"] as? [String: Any],
               let text = badge["text"] as? [String: Any],
               let runs = text["runs"] as? [[String: Any]],
               let first = runs.first,
               let textStr = first["text"] as? String,
               let parsed = parseTime(textStr) {
                return parsed
            }
        }
    }

    // 5. Subtitle runs — last segment after "•" separator may be duration
    if let subtitle = renderer["subtitle"] as? [String: Any],
       let runs = subtitle["runs"] as? [[String: Any]] {
        let allText = runs.compactMap { $0["text"] as? String }
        let segments = allText.split { $0 == " • " || $0.trimmingCharacters(in: .whitespaces) == "•" }
        if let lastSegment = segments.last,
           let lastText = lastSegment.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           let parsed = parseTime(lastText.trimmingCharacters(in: .whitespaces)) {
            return parsed
        }
    }

    // 6. flexColumns[1] subtitle text (for MusicResponsiveListItemRenderer)
    if let flexColumns = renderer["flexColumns"] as? [[String: Any]], flexColumns.count > 1 {
        let col = flexColumns[1]
        let flexRenderer = (col["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])
            ?? (col["musicResponsiveListItemColumnRenderer"] as? [String: Any])
        if let textDict = flexRenderer?["text"] as? [String: Any],
           let runs = textDict["runs"] as? [[String: Any]] {
            let allText = runs.compactMap { $0["text"] as? String }
            let segments = allText.split { $0 == " • " || $0.trimmingCharacters(in: .whitespaces) == "•" }
            if let lastSegment = segments.last,
               let lastText = lastSegment.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
               let parsed = parseTime(lastText.trimmingCharacters(in: .whitespaces)) {
                return parsed
            }
        }
    }

    return 0
}

private func parseTime(_ text: String) -> Int? {
    let parts = text.components(separatedBy: CharacterSet(charactersIn: ":.,")).compactMap { Int($0) }
    guard parts.count == 2 || parts.count == 3 else { return nil }
    if parts.count == 2 { return parts[0] * 60 + parts[1] }
    return parts[0] * 3600 + parts[1] * 60 + parts[2]
}

enum YTItem {
    case song(SongItem)
    case album(AlbumItem)
    case artist(ArtistItem)
    case playlist(PlaylistItem)
    case podcast(PodcastItem)
    case episode(EpisodeItem)

    var id: String {
        switch self {
        case .song(let s): return s.videoId
        case .album(let a): return a.browseId
        case .artist(let a): return a.browseId
        case .playlist(let p): return p.id
        case .podcast(let p): return p.browseId
        case .episode(let e): return e.videoId
        }
    }

    var title: String {
        switch self {
        case .song(let s): return s.title
        case .album(let a): return a.title
        case .artist(let a): return a.name
        case .playlist(let p): return p.title
        case .podcast(let p): return p.title
        case .episode(let e): return e.title
        }
    }

    var thumbnailUrl: String? {
        switch self {
        case .song(let s): return s.thumbnailUrl
        case .album(let a): return a.thumbnailUrl
        case .artist(let a): return a.thumbnailUrl
        case .playlist(let p): return p.thumbnailUrl
        case .podcast(let p): return p.thumbnailUrl
        case .episode(let e): return e.thumbnailUrl
        }
    }

    var subtitle: String {
        switch self {
        case .song(let s):
            let artistStr = s.artists.map(\.name).joined(separator: ", ")
            let effectiveDuration = s.duration > 0 ? s.duration : (DurationCache.get(s.videoId) ?? 0)
            let durationStr = effectiveDuration.formattedDuration
            if artistStr.isEmpty { return durationStr }
            if durationStr.isEmpty { return artistStr }
            return "\(artistStr) • \(durationStr)"
        case .album(let a):
            let names = a.artists.map(\.name)
            return names.isEmpty ? "" : names.joined(separator: ", ")
        case .artist: return ""
        case .playlist: return ""
        case .podcast: return ""
        case .episode(let e):
            let artistStr = e.artists.map(\.name).joined(separator: ", ")
            let effectiveDuration = e.duration > 0 ? e.duration : (DurationCache.get(e.videoId) ?? 0)
            let durationStr = effectiveDuration.formattedDuration
            if artistStr.isEmpty { return durationStr }
            if durationStr.isEmpty { return artistStr }
            return "\(artistStr) • \(durationStr)"
        }
    }

    var videoId: String? {
        switch self {
        case .song(let s): return s.videoId
        case .episode(let e): return e.videoId
        default: return nil
        }
    }

    static func fromResponsiveListItem(_ renderer: [String: Any]) -> YTItem? {
        guard let flexColumns = renderer["flexColumns"] as? [[String: Any]], !flexColumns.isEmpty else { return nil }

        let title = flexText(flexColumns, index: 0) ?? "Unknown"
        let thumbnailUrl = extractResponsiveThumbnail(renderer)
        let pageType = HomePageParser.extractPageType(renderer)
        let hasWatch = HomePageParser.hasWatchEndpoint(renderer)

        // Determine isEpisode
        let isNonMusicAudioTrack = (pageType == "MUSIC_PAGE_TYPE_NON_MUSIC_AUDIO_TRACK_PAGE")
        var isFirstSubtitleEpisode = false
        if flexColumns.count > 1 {
            let runs = flexTextRuns(flexColumns, index: 1)
            if let firstRun = runs.first, let text = firstRun["text"] as? String, text.trimmingCharacters(in: .whitespaces) == "Episode" {
                isFirstSubtitleEpisode = true
            }
        }
        var hasPodcastLink = false
        if flexColumns.count > 1 {
            let runs = flexTextRuns(flexColumns, index: 1)
            for run in runs {
                if let nav = run["navigationEndpoint"] as? [String: Any],
                   let browse = nav["browseEndpoint"] as? [String: Any],
                   let configs = browse["browseEndpointContextSupportedConfigs"] as? [String: Any],
                   let musicConfig = configs["browseEndpointContextMusicConfig"] as? [String: Any],
                   let pType = musicConfig["pageType"] as? String,
                   pType == "MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE" {
                    hasPodcastLink = true
                    break
                }
            }
        }
        let isEpisode = isNonMusicAudioTrack || isFirstSubtitleEpisode || hasPodcastLink

        if isEpisode {
            let videoId = extractVideoId(renderer) ?? ""
            if !videoId.isEmpty {
                let runs = flexTextRuns(flexColumns, index: 1)
                let segments = splitRunsBySeparator(runs)
                var podcastName: String? = nil
                if let lastSeg = segments.last {
                    podcastName = lastSeg.joined(separator: " ")
                }
                
                let episodeItem = EpisodeItem(
                    videoId: videoId,
                    title: title,
                    artists: podcastName.map { [YTArtist(name: $0)] } ?? [],
                    duration: parseDurationFromRenderer(renderer),
                    thumbnailUrl: thumbnailUrl,
                    publishDate: nil
                )
                return .episode(episodeItem)
            }
        }

        if hasWatch || pageType == nil {
            if let song = SongItem.from(renderer) {
                return .song(song)
            }
        }

        guard let browseId = extractTwoRowBrowseId(renderer) else {
            if hasWatch, let song = SongItem.from(renderer) {
                return .song(song)
            }
            return nil
        }

        switch pageType {
        case "MUSIC_PAGE_TYPE_ALBUM", "MUSIC_PAGE_TYPE_AUDIOBOOK":
            let runs = flexTextRuns(flexColumns, index: 1)
            let segments = splitRunsBySeparator(runs)
            var artists: [YTArtist] = []
            var year: Int? = nil

            for seg in segments {
                if let firstWord = seg.first {
                    if let y = Int(firstWord), y > 1900 && y < 2100 {
                        year = y
                    } else if firstWord != "Album" && firstWord != "EP" && firstWord != "Single" {
                        for artistName in seg {
                            artists.append(YTArtist(name: artistName, id: nil))
                        }
                    }
                }
            }

            let albumItem = AlbumItem(
                browseId: browseId,
                title: title,
                artists: artists,
                year: year,
                thumbnailUrl: thumbnailUrl,
                playlistId: extractPlaylistId(renderer),
                isExplicit: false
            )
            return .album(albumItem)

        case "MUSIC_PAGE_TYPE_ARTIST":
            let artistItem = ArtistItem(
                browseId: browseId,
                name: title,
                thumbnailUrl: thumbnailUrl,
                isSubscribed: false
            )
            return .artist(artistItem)

        case "MUSIC_PAGE_TYPE_PLAYLIST":
            let runs = flexTextRuns(flexColumns, index: 1)
            let segments = splitRunsBySeparator(runs)
            var author: String? = nil
            if let firstSeg = segments.first {
                author = firstSeg.joined(separator: " ")
            }
            let playlistItem = PlaylistItem(
                id: browseId,
                title: title,
                author: author,
                thumbnailUrl: thumbnailUrl,
                songCount: nil
            )
            return .playlist(playlistItem)

        case "MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE":
            let podcastItem = PodcastItem(
                browseId: browseId,
                title: title,
                author: nil,
                thumbnailUrl: thumbnailUrl
            )
            return .podcast(podcastItem)

        case "MUSIC_PAGE_TYPE_NON_MUSIC_AUDIO_TRACK_PAGE":
            if let episode = EpisodeItem.from(renderer) {
                return .episode(episode)
            }

        default:
            if browseId.hasPrefix("FElike_") || browseId.hasPrefix("VL") {
                let playlistItem = PlaylistItem(
                    id: browseId,
                    title: title,
                    author: nil,
                    thumbnailUrl: thumbnailUrl,
                    songCount: nil
                )
                return .playlist(playlistItem)
            } else if browseId.hasPrefix("UC") {
                let artistItem = ArtistItem(
                    browseId: browseId,
                    name: title,
                    thumbnailUrl: thumbnailUrl,
                    isSubscribed: false
                )
                return .artist(artistItem)
            } else if browseId.hasPrefix("MPREb_") {
                let albumItem = AlbumItem(
                    browseId: browseId,
                    title: title,
                    artists: [],
                    year: nil,
                    thumbnailUrl: thumbnailUrl,
                    playlistId: nil,
                    isExplicit: false
                )
                return .album(albumItem)
            }
        }

        return nil
    }
}

struct SongItem {
    var videoId: String
    var title: String
    var artists: [YTArtist]
    var album: String?
    var albumId: String?
    var duration: Int
    var thumbnailUrl: String?
    var isExplicit: Bool
    var playlistId: String?
    var likeStatus: String?

    static func from(_ renderer: [String: Any]) -> SongItem? {
        guard let videoId = extractVideoId(renderer) else { return nil }
        let duration = parseDurationFromRenderer(renderer)
        let playlistId = extractPlaylistId(renderer)

        if let flexColumns = renderer["flexColumns"] as? [[String: Any]] {
            return fromResponsiveListItem(renderer: renderer, flexColumns: flexColumns, videoId: videoId, duration: duration, playlistId: playlistId)
        }
        return fromTwoRowItem(renderer: renderer, videoId: videoId, duration: duration, playlistId: playlistId)
    }

    private static let nonArtistLabels: Set<String> = [
        "song", "video", "track", "music", "podcast", "episode",
        "album", "playlist", "released", "plays", "views",
        "downloads", "listeners", "subscribers", "likes"
    ]
    private static let nonArtistPatterns: [String] = [
        "^\\d+(\\.\\d+)?[KMBT]?\\s*(views|downloads|listeners|subscribers|plays|likes)?$",
        "^\\d{4}$",                      // bare year
        "^[\\d,\\.]+[KMBT]?$",           // numeric-only (e.g. "1.2M")
        "^[\\d,\\.]+[KMBT]?\\s+likes?$"  // "500K likes", "1.2M like"
    ]
    private static let conjunctions: Set<String> = [",", "&", "and", "feat.", "ft.", "featuring"]

    private static func isViewCountOrJunk(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        if lower.isEmpty || lower == "•" || lower == "·" { return true }
        if conjunctions.contains(lower) || nonArtistLabels.contains(lower) { return true }
        for pattern in nonArtistPatterns {
            if lower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        }
        return false
    }

    private static func isArtistSegment(_ text: String) -> Bool {
        return !isViewCountOrJunk(text)
    }

    // Strips the YouTube "- Topic" auto-generated channel suffix and bare years from a name.
    private static func cleanArtistName(_ name: String) -> String {
        var s = name
        for suffix in [" - Topic", " - topic"] {
            if s.hasSuffix(suffix) { s = String(s.dropLast(suffix.count)) }
        }
        // Remove trailing bare year like " (2023)" or " [2023]"
        if let r = try? NSRegularExpression(pattern: "\\s*[\\(\\[]\\d{4}[\\)\\]]\\s*$") {
            s = r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isArtistRun(_ run: [String: Any]) -> Bool {
        guard let text = run["text"] as? String else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if isViewCountOrJunk(trimmed) { return false }
        if let nav = run["navigationEndpoint"] as? [String: Any],
           let browse = nav["browseEndpoint"] as? [String: Any],
           let bid = browse["browseId"] as? String,
           bid.hasPrefix("MPREb_") { return false }
        return true
    }

    private static func fromResponsiveListItem(renderer: [String: Any], flexColumns: [[String: Any]], videoId: String, duration: Int, playlistId: String?) -> SongItem? {
        let title = flexText(flexColumns, index: 0) ?? "Unknown"
        let runs = flexTextRuns(flexColumns, index: 1)
        let segments = splitRunsBySeparator(runs)
        let artists: [YTArtist]
        let album: String?
        if !segments.isEmpty {
            let artistSegments = segments.drop { seg in
                seg.allSatisfy { !isArtistSegment($0) }
            }
            if artistSegments.isEmpty {
                artists = segments[0].filter { isArtistSegment($0) }.map { YTArtist(name: cleanArtistName($0)) }
                album = segments.count > 1 ? segments[1].first : nil
            } else {
                artists = artistSegments.first!.filter { isArtistSegment($0) }.map { YTArtist(name: cleanArtistName($0)) }
                album = artistSegments.dropFirst().first?.first
            }
        } else {
            artists = []
            album = nil
        }
        let thumbnailUrl = extractResponsiveThumbnail(renderer)
        return SongItem(
            videoId: videoId, title: title, artists: artists, album: album,
            duration: duration, thumbnailUrl: thumbnailUrl, isExplicit: false, playlistId: playlistId
        )
    }

    private static func fromTwoRowItem(renderer: [String: Any], videoId: String, duration: Int, playlistId: String?) -> SongItem? {
        let title = extractRunsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let thumbnailUrl = extractTwoRowThumbnail(renderer)
        var artists: [YTArtist] = []
        var album: String?
        if let subtitleDict = renderer["subtitle"] as? [String: Any],
           let runs = subtitleDict["runs"] as? [[String: Any]] {
            for run in runs {
                guard let text = run["text"] as? String else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed == "•" { continue }
                if let nav = run["navigationEndpoint"] as? [String: Any],
                   let browse = nav["browseEndpoint"] as? [String: Any],
                   let bid = browse["browseId"] as? String,
                   bid.hasPrefix("MPREb_") {
                    album = trimmed
                } else if isArtistRun(run) {
                    artists.append(YTArtist(name: cleanArtistName(trimmed)))
                }
            }
        }
        return SongItem(
            videoId: videoId, title: title, artists: artists, album: album,
            duration: duration, thumbnailUrl: thumbnailUrl, isExplicit: false, playlistId: playlistId
        )
    }
}

struct AlbumItem {
    var browseId: String
    var title: String
    var artists: [YTArtist]
    var year: Int?
    var thumbnailUrl: String?
    var playlistId: String?
    var isExplicit: Bool

    static func from(_ renderer: [String: Any]) -> AlbumItem? {
        guard let browseId = extractTwoRowBrowseId(renderer) else { return nil }
        let title = extractRunsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let thumbnailUrl = extractTwoRowThumbnail(renderer)
        return AlbumItem(
            browseId: browseId,
            title: title,
            artists: [],
            thumbnailUrl: thumbnailUrl,
            playlistId: extractPlaylistId(renderer),
            isExplicit: false
        )
    }
}

struct ArtistItem {
    var browseId: String
    var name: String
    var thumbnailUrl: String?
    var isSubscribed: Bool

    static func from(_ renderer: [String: Any]) -> ArtistItem? {
        guard let browseId = extractTwoRowBrowseId(renderer) else { return nil }
        let name = extractRunsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let thumbnailUrl = extractTwoRowThumbnail(renderer)
        return ArtistItem(browseId: browseId, name: name, thumbnailUrl: thumbnailUrl, isSubscribed: false)
    }
}

struct PlaylistItem {
    var id: String
    var title: String
    var author: String?
    var thumbnailUrl: String?
    var songCount: Int?

    static func from(_ renderer: [String: Any]) -> PlaylistItem? {
        guard let browseId = extractTwoRowBrowseId(renderer) else { return nil }
        let title = extractRunsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let thumbnailUrl = extractTwoRowThumbnail(renderer)
        let subtitleRuns = extractRunsTextArray(renderer["subtitle"] as? [String: Any])
        return PlaylistItem(
            id: browseId,
            title: title,
            author: subtitleRuns.first,
            thumbnailUrl: thumbnailUrl
        )
    }
}

struct PodcastItem {
    var browseId: String
    var title: String
    var author: String?
    var thumbnailUrl: String?

    static func from(_ renderer: [String: Any]) -> PodcastItem? {
        guard let browseId = extractTwoRowBrowseId(renderer) else { return nil }
        let title = extractRunsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let thumbnailUrl = extractTwoRowThumbnail(renderer)
        return PodcastItem(browseId: browseId, title: title, thumbnailUrl: thumbnailUrl)
    }
}

struct EpisodeItem {
    var videoId: String
    var title: String
    var artists: [YTArtist]
    var duration: Int
    var thumbnailUrl: String?
    var publishDate: String?

    static func from(_ renderer: [String: Any]) -> EpisodeItem? {
        guard let videoId = extractVideoId(renderer) else { return nil }
        let title = extractRunsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let thumbnailUrl = extractTwoRowThumbnail(renderer)
        let duration = parseDurationFromRenderer(renderer)
        return EpisodeItem(videoId: videoId, title: title, artists: [], duration: duration, thumbnailUrl: thumbnailUrl)
    }
}

// MARK: - Convenience Conversions

extension EpisodeItem {
    func toSongItem() -> SongItem {
        SongItem(
            videoId: videoId,
            title: title,
            artists: artists,
            album: nil,
            albumId: nil,
            duration: duration,
            thumbnailUrl: thumbnailUrl,
            isExplicit: false,
            playlistId: nil,
            likeStatus: nil
        )
    }
}

// MARK: - Convenience Init from Entities

extension SongItem {
    init(entity: SongEntity) {
        self.videoId = entity.id
        self.title = entity.title
        self.artists = entity.artistName.map { [YTArtist(name: $0)] } ?? []
        self.album = entity.albumName
        self.albumId = nil
        self.duration = entity.duration
        self.thumbnailUrl = entity.thumbnailUrl
        self.isExplicit = false
        self.playlistId = nil
        self.likeStatus = nil
    }
}

extension AlbumItem {
    init(entity: AlbumEntity) {
        self.browseId = entity.id
        self.title = entity.title
        self.artists = []
        self.year = nil
        self.thumbnailUrl = entity.thumbnailUrl
        self.playlistId = entity.playlistId
        self.isExplicit = false
    }
}

extension ArtistItem {
    init(entity: ArtistEntity) {
        self.browseId = entity.id
        self.name = entity.name
        self.thumbnailUrl = entity.thumbnailUrl
        self.isSubscribed = entity.bookmarkedAt != nil
    }
}

extension PlaylistItem {
    init(entity: PlaylistEntity) {
        self.id = entity.id
        self.title = entity.name
        self.author = nil
        self.thumbnailUrl = nil
        self.songCount = entity.remoteSongCount
    }
}

// MARK: - Extract Helpers

private func extractVideoId(_ renderer: [String: Any]) -> String? {
    // 1. Top-level videoId (rare, search result items)
    if let videoId = renderer["videoId"] as? String { return videoId }

    // 2. playlistItemData.videoId — primary for playlist / album track rows
    if let pid = renderer["playlistItemData"] as? [String: Any],
       let videoId = pid["videoId"] as? String { return videoId }

    // 3. flexColumns[0] run navigationEndpoint.watchEndpoint.videoId
    if let flexColumns = renderer["flexColumns"] as? [[String: Any]],
       let firstCol = flexColumns.first,
       let colRenderer = firstCol["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
       let runs = (colRenderer["text"] as? [String: Any])?["runs"] as? [[String: Any]],
       let firstRun = runs.first,
       let nav = firstRun["navigationEndpoint"] as? [String: Any],
       let watch = nav["watchEndpoint"] as? [String: Any],
       let videoId = watch["videoId"] as? String { return videoId }

    // 4. overlay musicPlayButtonRenderer.playNavigationEndpoint.watchEndpoint.videoId
    if let overlay = renderer["overlay"] as? [String: Any],
       let overlayRenderer = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
       let content = overlayRenderer["content"] as? [String: Any],
       let playButton = content["musicPlayButtonRenderer"] as? [String: Any],
       let nav = playButton["playNavigationEndpoint"] as? [String: Any],
       let watch = nav["watchEndpoint"] as? [String: Any],
       let videoId = watch["videoId"] as? String { return videoId }

    // 5. navigationEndpoint.watchEndpoint.videoId (legacy)
    if let nav = renderer["navigationEndpoint"] as? [String: Any],
       let watch = nav["watchEndpoint"] as? [String: Any],
       let videoId = watch["videoId"] as? String { return videoId }

    return nil
}

private func extractTwoRowBrowseId(_ renderer: [String: Any]) -> String? {
    guard let nav = renderer["navigationEndpoint"] as? [String: Any],
          let browse = nav["browseEndpoint"] as? [String: Any],
          let bid = browse["browseId"] as? String else { return nil }
    return bid
}

private func extractPlaylistId(_ renderer: [String: Any]) -> String? {
    guard let nav = renderer["navigationEndpoint"] as? [String: Any],
          let watch = nav["watchEndpoint"] as? [String: Any],
          let pid = watch["playlistId"] as? String else { return nil }
    return pid
}

private func extractTwoRowThumbnail(_ renderer: [String: Any]) -> String? {
    if let thumb = extractThumbnailFrom(renderer["thumbnail"] as? [String: Any]) {
        return thumb
    }
    if let thumbRenderer = renderer["thumbnailRenderer"] as? [String: Any],
       let musicThumb = thumbRenderer["musicThumbnailRenderer"] as? [String: Any] {
        return extractThumbnailFrom(musicThumb)
    }
    return nil
}

private func extractThumbnailFrom(_ dict: [String: Any]?) -> String? {
    guard let thumb = dict?["thumbnail"] as? [String: Any],
          let thumbnails = thumb["thumbnails"] as? [[String: Any]],
          let last = thumbnails.last,
          let url = last["url"] as? String else { return nil }
    return url
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

// MARK: - Responsive List Item Helpers

private func flexText(_ flexColumns: [[String: Any]], index: Int) -> String? {
    guard index < flexColumns.count else { return nil }
    let col = flexColumns[index]
    let flexRenderer = (col["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])
        ?? (col["musicResponsiveListItemColumnRenderer"] as? [String: Any])
    guard let textDict = flexRenderer?["text"] as? [String: Any],
          let runs = textDict["runs"] as? [[String: Any]],
          let first = runs.first,
          let text = first["text"] as? String else { return nil }
    return text
}

private func flexTextRuns(_ flexColumns: [[String: Any]], index: Int) -> [[String: Any]] {
    guard index < flexColumns.count else { return [] }
    let col = flexColumns[index]
    let flexRenderer = (col["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])
        ?? (col["musicResponsiveListItemColumnRenderer"] as? [String: Any])
    guard let textDict = flexRenderer?["text"] as? [String: Any],
          let runs = textDict["runs"] as? [[String: Any]] else { return [] }
    return runs
}

private func splitRunsBySeparator(_ runs: [[String: Any]]) -> [[String]] {
    let separators: Set<String> = ["•", "·", ",", "&", "and", "feat.", "ft.", "featuring"]
    var segments: [[String]] = []
    var current: [String] = []
    for run in runs {
        guard let text = run["text"] as? String else { continue }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if separators.contains(trimmed.lowercased()) {
            if !current.isEmpty {
                segments.append(current)
                current = []
            }
        } else if !trimmed.isEmpty {
            current.append(trimmed)
        }
    }
    if !current.isEmpty {
        segments.append(current)
    }
    return segments
}

private func extractResponsiveThumbnail(_ renderer: [String: Any]) -> String? {
    if let thumbnail = renderer["thumbnail"] as? [String: Any] {
        if let musicThumb = thumbnail["musicThumbnailRenderer"] as? [String: Any],
           let thumb = musicThumb["thumbnail"] as? [String: Any],
           let thumbnails = thumb["thumbnails"] as? [[String: Any]],
           let last = thumbnails.last,
           let url = last["url"] as? String {
            return url
        }
        if let thumbnails = thumbnail["thumbnails"] as? [[String: Any]],
           let last = thumbnails.last,
           let url = last["url"] as? String {
            return url
        }
    }
    return nil
}
