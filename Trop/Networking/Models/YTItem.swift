//
//  YTItem.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import Foundation

struct YTArtist: Codable, Hashable {
    var name: String
    var id: String?
}

/// Bare 4-digit release year segment.
private func parseYear(_ text: String) -> Int? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard trimmed.count == 4, let year = Int(trimmed), year > 1900, year < 2100 else { return nil }
    return year
}

/// Subtitle stats scraped from a result's runs.
private struct ItemStats {
    var viewCount: Int64?
    var year: Int?
    var startsWithVideo = false
}

/// Scans subtitle segments for view counts and years.
private func extractItemStats(from segments: [[String]]) -> ItemStats {
    var stats = ItemStats()
    for seg in segments {
        for text in seg {
            if stats.viewCount == nil, let v = CountFormat.parseCompactCount(text) { stats.viewCount = v }
            if stats.year == nil, let y = parseYear(text) { stats.year = y }
        }
    }
    stats.startsWithVideo = segments.first?.first?
        .trimmingCharacters(in: .whitespaces).lowercased() == "video"
    return stats
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
                var podcastName: String?
                if let lastSeg = segments.last {
                    podcastName = lastSeg.joined(separator: " ")
                }

                let episodeItem = EpisodeItem(
                    videoId: videoId,
                    title: title,
                    artists: podcastName.map { [YTArtist(name: ArtistCredits.cleanedName($0))] } ?? [],
                    duration: DurationFormat.parseRendererDuration(renderer),
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
            var year: Int?

            for seg in segments {
                if let firstWord = seg.first,
                   let y = Int(firstWord), y > 1900 && y < 2100 {
                    year = y
                }
            }
            let artists = ArtistCredits.parse(runs: runs).map {
                YTArtist(name: $0.name, id: $0.browseId)
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
            var author: String?
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

struct SongItem: Codable, Hashable {
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
    /// Parsed subtitle stats (search results only; nil when absent).
    /// Optional so previously persisted queues keep decoding.
    var viewCount: Int64?
    var year: Int?
    var isVideo: Bool?
    /// Watch-endpoint music type (`MUSIC_VIDEO_TYPE_ATV` for auto-generated
    /// art-tracks), when the row carried one. Nil for stored rows parsed
    /// before this existed — previously persisted queues keep decoding.
    var musicVideoType: String?

    /// True for music-video results (subtitle starts with "Video").
    var isMusicVideo: Bool { isVideo == true }

    static func from(_ renderer: [String: Any]) -> SongItem? {
        guard let videoId = extractVideoId(renderer) else {
            return nil
        }
        let duration = DurationFormat.parseRendererDuration(renderer)
        let playlistId = extractPlaylistId(renderer)

        if let flexColumns = renderer["flexColumns"] as? [[String: Any]] {
            return fromResponsiveListItem(renderer: renderer, flexColumns: flexColumns, videoId: videoId, duration: duration, playlistId: playlistId)
        }
        return fromTwoRowItem(renderer: renderer, videoId: videoId, duration: duration, playlistId: playlistId)
    }

    private static func fromResponsiveListItem(
        renderer: [String: Any],
        flexColumns: [[String: Any]],
        videoId: String,
        duration: Int,
        playlistId: String?
    ) -> SongItem? {
        let title = flexText(flexColumns, index: 0) ?? "Unknown"
        let runs = flexTextRuns(flexColumns, index: 1)
        let segments = splitRunsBySeparator(runs)
        let artists: [YTArtist]
        var album: String?
        var albumId: String?

        // Try flexColumns[2] first — dedicated album column with navigation endpoint (like Metrolist)
        if flexColumns.indices.contains(2) {
            let albumRuns = flexTextRuns(flexColumns, index: 2)
            if let firstRun = albumRuns.first,
               let name = firstRun["text"] as? String,
               let nav = firstRun["navigationEndpoint"] as? [String: Any],
               let browse = nav["browseEndpoint"] as? [String: Any],
               let bid = browse["browseId"] as? String {
                album = name
                albumId = bid
            }
        }

        if !segments.isEmpty {
            let artistSegments = segments.drop { seg in seg.allSatisfy { !ArtistCredits.isArtistName($0) } }
            let credits = ArtistCredits.parse(runs: runs)
            func creditId(for rawText: String) -> String? {
                let cleaned = ArtistCredits.cleanedName(rawText)
                return credits.first { $0.name == cleaned }?.browseId
            }
            if artistSegments.isEmpty {
                artists = segments[0].filter { ArtistCredits.isArtistName($0) }.map {
                    YTArtist(name: ArtistCredits.cleanedName($0), id: creditId(for: $0))
                }
                if album == nil && segments.count > 1 {
                    album = segments[1].first
                }
            } else {
                var collected: [YTArtist] = []
                for seg in artistSegments {
                    collected.append(contentsOf: seg.filter { ArtistCredits.isArtistName($0) }.map {
                        YTArtist(name: ArtistCredits.cleanedName($0), id: creditId(for: $0))
                    })
                }
                artists = collected
                if album == nil {
                    album = artistSegments.dropFirst().first?.first
                }
            }
        } else {
            artists = []
        }
        let thumbnailUrl = extractResponsiveThumbnail(renderer)
        let stats = extractItemStats(from: segments)
        return SongItem(
            videoId: videoId, title: title, artists: artists, album: album, albumId: albumId,
            duration: duration, thumbnailUrl: thumbnailUrl, isExplicit: false, playlistId: playlistId,
            viewCount: stats.viewCount, year: stats.year, isVideo: stats.startsWithVideo ? true : nil,
            musicVideoType: VideoAvailability.rowMusicVideoType(renderer)
        )
    }

    private static func fromTwoRowItem(renderer: [String: Any], videoId: String, duration: Int, playlistId: String?) -> SongItem? {
        let title = InnerTubeJSON.runsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let thumbnailUrl = extractTwoRowThumbnail(renderer)
        var artists: [YTArtist] = []
        var album: String?
        var albumId: String?
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
                    albumId = bid
                }
            }
            artists = ArtistCredits.parse(runs: runs).map { YTArtist(name: $0.name, id: $0.browseId) }
        }
        let subTexts = (renderer["subtitle"] as? [String: Any])
            .flatMap { $0["runs"] as? [[String: Any]] }?
            .compactMap { ($0["text"] as? String)?.trimmingCharacters(in: .whitespaces) } ?? []
        var subSegments: [[String]] = [[]]
        for text in subTexts {
            if text == "•" || text == "·" {
                subSegments.append([])
            } else if !text.isEmpty {
                subSegments[subSegments.count - 1].append(text)
            }
        }
        let stats = extractItemStats(from: subSegments)
        return SongItem(
            videoId: videoId, title: title, artists: artists, album: album, albumId: albumId,
            duration: duration, thumbnailUrl: thumbnailUrl, isExplicit: false, playlistId: playlistId,
            viewCount: stats.viewCount, year: stats.year, isVideo: stats.startsWithVideo ? true : nil,
            musicVideoType: VideoAvailability.rowMusicVideoType(renderer)
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
        let title = InnerTubeJSON.runsText(renderer["title"] as? [String: Any]) ?? "Unknown"
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
        let name = InnerTubeJSON.runsText(renderer["title"] as? [String: Any]) ?? "Unknown"
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
        let title = InnerTubeJSON.runsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let thumbnailUrl = extractTwoRowThumbnail(renderer)
        let subtitleRuns = InnerTubeJSON.runsTexts(renderer["subtitle"] as? [String: Any])
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
        let title = InnerTubeJSON.runsText(renderer["title"] as? [String: Any]) ?? "Unknown"
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
    var descriptionText: String?
    var viewsText: String?

    static func from(_ renderer: [String: Any]) -> EpisodeItem? {
        guard let videoId = extractVideoId(renderer) else { return nil }
        let title = InnerTubeJSON.runsText(renderer["title"] as? [String: Any]) ?? "Unknown"
        let thumbnailUrl = extractTwoRowThumbnail(renderer)
        var duration = DurationFormat.parseRendererDuration(renderer)
        if duration == 0,
           let progress = renderer["playbackProgress"] as? [String: Any],
           let progressRenderer = progress["musicPlaybackProgressRenderer"] as? [String: Any],
           let durationText = InnerTubeJSON.runsText(progressRenderer["durationText"] as? [String: Any]),
           !durationText.isEmpty {
            duration = DurationFormat.parseClock(durationText)
                ?? DurationFormat.parseSpoken(durationText)
                ?? 0
        }
        // Subtitle runs carry "views • date" alongside the duration.
        var publishDate: String?
        var viewsText: String?
        if let flexColumns = renderer["flexColumns"] as? [[String: Any]] {
            for run in flexTextRuns(flexColumns, index: 1) {
                guard let text = run["text"] as? String else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed == "•" || trimmed.contains(":") { continue }
                let lower = trimmed.lowercased()
                if lower.contains("view") || lower.contains("listening") || lower.contains("download") {
                    viewsText = viewsText ?? trimmed
                } else if publishDate == nil {
                    publishDate = trimmed
                }
            }
        }
        return EpisodeItem(
            videoId: videoId,
            title: title,
            artists: [],
            duration: duration,
            thumbnailUrl: thumbnailUrl,
            publishDate: publishDate,
            descriptionText: InnerTubeJSON.runsText(renderer["description"] as? [String: Any]),
            viewsText: viewsText
        )
    }

    /// "17k views • 4 hr ago • 1 hr 23 mins" meta line under each episode.
    var metaLine: String {
        var parts: [String] = []
        if let views = viewsText, !views.isEmpty { parts.append(views) }
        if let date = publishDate, !date.isEmpty { parts.append(date) }
        let durationStr = duration.wordsDuration
        if !durationStr.isEmpty { parts.append(durationStr) }
        return parts.joined(separator: " • ")
    }
}

// MARK: - Web URL

extension SongItem {
    var webUrl: String {
        "https://music.youtube.com/watch?v=\(videoId)"
    }

    var artistNamesDisplay: String {
        artists.filter { !$0.name.isEmpty }.map(\.name).joined(separator: ", ")
    }

    /// "Artists • m:ss" subtitle line used by song rows.
    func subtitleLine(duration: Int) -> String {
        let durationStr = duration.formattedDuration
        if artistNamesDisplay.isEmpty { return durationStr }
        if durationStr.isEmpty { return artistNamesDisplay }
        return "\(artistNamesDisplay) • \(durationStr)"
    }

    var firstAlbumBrowseId: String? {
        albumId
    }
}

extension EpisodeItem {
    var webUrl: String {
        "https://music.youtube.com/watch?v=\(videoId)"
    }
}

extension YTItem {
    var firstAlbumBrowseId: String? {
        switch self {
        case .song(let s): return s.firstAlbumBrowseId
        default: return nil
        }
    }

    var webUrl: String? {
        switch self {
        case .song(let s): return s.webUrl
        case .episode(let e): return e.webUrl
        case .album(let a):
            guard let pid = a.playlistId else { return nil }
            return "https://music.youtube.com/playlist?list=\(pid)"
        case .artist(let a):
            return "https://music.youtube.com/channel/\(a.browseId)"
        case .playlist(let p):
            return "https://music.youtube.com/playlist?list=\(p.id)"
        case .podcast:
            return nil
        }
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
        self.title = entity.title.isEmpty ? "Unknown" : entity.title
        self.artists = entity.artistName.map { [YTArtist(name: ArtistCredits.cleanedName($0))] } ?? []
        self.album = entity.albumName
        self.albumId = nil
        self.duration = entity.duration
        self.thumbnailUrl = entity.thumbnailUrl
        self.isExplicit = false
        self.playlistId = nil
        self.likeStatus = nil
    }

    init(entity: DownloadedTrackEntity) {
        self.videoId = entity.id
        self.title = entity.title
        self.artists = entity.artist
            .split(separator: ",")
            .map { YTArtist(name: ArtistCredits.cleanedName(String($0).trimmingCharacters(in: .whitespaces))) }
            .filter { !$0.name.isEmpty }
        self.album = nil
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
        self.thumbnailUrl = entity.thumbnailUrl
        self.songCount = entity.remoteSongCount
    }
}

extension Sequence where Element == SongEntity {
    /// Maps stored songs to player items.
    func toSongItems() -> [SongItem] {
        map { SongItem(entity: $0) }
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
    if let thumb = InnerTubeJSON.nestedThumbnailURL(renderer) {
        return thumb
    }
    if let thumbRenderer = renderer["thumbnailRenderer"] as? [String: Any],
       let musicThumb = thumbRenderer["musicThumbnailRenderer"] as? [String: Any] {
        return InnerTubeJSON.nestedThumbnailURL(musicThumb)
    }
    return nil
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
           let url = InnerTubeJSON.nestedThumbnailURL(musicThumb) {
            return url
        }
        if let url = InnerTubeJSON.lastThumbnailURL(thumbnail["thumbnails"] as? [[String: Any]]) {
            return url
        }
    }
    return nil
}
